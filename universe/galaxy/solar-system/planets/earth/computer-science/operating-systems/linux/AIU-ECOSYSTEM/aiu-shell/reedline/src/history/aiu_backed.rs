use super::{
    base::{CommandLineSearch, SearchDirection, SearchQuery},
    History, HistoryItem, HistoryItemId, HistorySessionId,
};
use crate::{
    history::HistoryTimestamp,
    result::{ReedlineError, ReedlineErrorVariants},
    Result,
};
use rusqlite::{params, params_from_iter, types::Value, Connection};
use std::{
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const NANOS_PER_MILLI: i64 = 1_000_000;
static ROW_COUNTER: AtomicU64 = AtomicU64::new(0);

pub struct AiuBackedHistory {
    db: Connection,
    session: Option<HistorySessionId>,
    has_deleted_column: bool,
    has_author_column: bool,
}

fn history_error(err: impl std::fmt::Display) -> ReedlineError {
    ReedlineError(ReedlineErrorVariants::HistoryDatabaseError(err.to_string()))
}

fn now_nanos() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_nanos() as i64)
        .unwrap_or(0)
}

fn new_row_id() -> String {
    let counter = ROW_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("{:x}-{:x}-{:x}", now_nanos(), std::process::id(), counter)
}

fn start_nanos(item: &HistoryItem) -> Option<i64> {
    item.start_timestamp
        .as_ref()
        .map(|stamp| stamp.to_millis() * NANOS_PER_MILLI)
}

fn duration_nanos(item: &HistoryItem) -> i64 {
    item.duration
        .map(|elapsed| elapsed.as_nanos() as i64)
        .unwrap_or(-1)
}

fn exit_value(item: &HistoryItem) -> i64 {
    item.exit_status.unwrap_or(-1)
}

fn session_text(item: &HistoryItem) -> String {
    item.session_id
        .as_ref()
        .map(|session| session.0.to_string())
        .unwrap_or_default()
}

fn row_to_item(row: &rusqlite::Row) -> rusqlite::Result<HistoryItem> {
    let timestamp: i64 = row.get(1)?;
    let duration: i64 = row.get(2)?;
    let exit: i64 = row.get(3)?;
    let cwd: String = row.get(5)?;
    let session: String = row.get(6)?;
    let hostname: String = row.get(7)?;
    Ok(HistoryItem {
        id: Some(HistoryItemId::new(row.get(0)?)),
        start_timestamp: Some(HistoryTimestamp::from_millis(timestamp / NANOS_PER_MILLI)),
        command_line: row.get(4)?,
        session_id: session.parse::<i64>().ok().map(HistorySessionId::new),
        hostname: if hostname.is_empty() { None } else { Some(hostname) },
        cwd: if cwd.is_empty() { None } else { Some(cwd) },
        duration: if duration >= 0 {
            Some(Duration::from_nanos(duration as u64))
        } else {
            None
        },
        exit_status: if exit == -1 { None } else { Some(exit) },
        more_info: None,
    })
}

impl AiuBackedHistory {
    pub fn database_path() -> PathBuf {
        let data_home = std::env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .or_else(|| {
                std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".local").join("share"))
            })
            .unwrap_or_else(|| PathBuf::from("."));
        data_home.join("aiu-shell-history").join("history.db")
    }

    pub fn with_file(
        _file: PathBuf,
        session: Option<HistorySessionId>,
        _session_timestamp: Option<HistoryTimestamp>,
    ) -> Result<Self> {
        Self::open_path(&Self::database_path(), session)
    }

    pub fn open_path(path: &Path, session: Option<HistorySessionId>) -> Result<Self> {
        if let Some(directory) = path.parent() {
            std::fs::create_dir_all(directory).map_err(history_error)?;
        }
        let db = Connection::open(path).map_err(history_error)?;
        Self::from_connection(db, session)
    }

    pub fn in_memory() -> Result<Self> {
        Self::from_connection(Connection::open_in_memory().map_err(history_error)?, None)
    }

    fn from_connection(db: Connection, session: Option<HistorySessionId>) -> Result<Self> {
        db.busy_timeout(Duration::from_secs(5)).map_err(history_error)?;
        db.pragma_update(None, "journal_mode", "wal").map_err(history_error)?;
        db.pragma_update(None, "synchronous", "normal").map_err(history_error)?;
        db.execute_batch(
            "create table if not exists history (
                id text primary key,
                timestamp integer not null,
                duration integer not null,
                exit integer not null,
                command text not null,
                cwd text not null,
                session text not null,
                hostname text not null,
                unique(timestamp, cwd, command)
            );
            create index if not exists idx_history_timestamp on history(timestamp);
            create index if not exists idx_history_command on history(command);",
        )
        .map_err(history_error)?;
        let has_deleted_column = Self::has_column(&db, "deleted_at")?;
        let has_author_column = Self::has_column(&db, "author")?;
        Ok(Self {
            db,
            session,
            has_deleted_column,
            has_author_column,
        })
    }

    fn has_column(db: &Connection, name: &str) -> Result<bool> {
        let count: i64 = db
            .query_row(
                "select count(*) from pragma_table_info(?1) where name = ?2",
                params![String::from("history"), name],
                |row| row.get(0),
            )
            .map_err(history_error)?;
        Ok(count > 0)
    }

    fn where_clause(&self, query: &SearchQuery) -> (String, Vec<Value>) {
        let mut parts: Vec<String> = vec![String::from("1 = 1")];
        let mut values: Vec<Value> = Vec::new();
        if self.has_deleted_column {
            parts.push(String::from("deleted_at is null"));
        }
        let filter = &query.filter;
        match &filter.command_line {
            Some(CommandLineSearch::Prefix(text)) => {
                parts.push(String::from("substr(command, 1, length(?)) = ?"));
                values.push(Value::Text(text.clone()));
                values.push(Value::Text(text.clone()));
            }
            Some(CommandLineSearch::Substring(text)) => {
                parts.push(String::from("instr(command, ?) > 0"));
                values.push(Value::Text(text.clone()));
            }
            Some(CommandLineSearch::Exact(text)) => {
                parts.push(String::from("command = ?"));
                values.push(Value::Text(text.clone()));
            }
            None => {}
        }
        if let Some(hostname) = &filter.hostname {
            parts.push(String::from("hostname = ?"));
            values.push(Value::Text(hostname.clone()));
        }
        if let Some(cwd) = &filter.cwd_exact {
            parts.push(String::from("cwd = ?"));
            values.push(Value::Text(cwd.clone()));
        }
        if let Some(prefix) = &filter.cwd_prefix {
            parts.push(String::from("substr(cwd, 1, length(?)) = ?"));
            values.push(Value::Text(prefix.clone()));
            values.push(Value::Text(prefix.clone()));
        }
        match filter.exit_successful {
            Some(true) => parts.push(String::from("exit = 0")),
            Some(false) => parts.push(String::from("exit != 0")),
            None => {}
        }
        if let Some(session) = &filter.session {
            parts.push(String::from("session = ?"));
            values.push(Value::Text(session.0.to_string()));
        }
        let backward = query.direction == SearchDirection::Backward;
        if let Some(stamp) = query.start_time.as_ref() {
            parts.push(format!("timestamp {} ?", if backward { "<=" } else { ">=" }));
            values.push(Value::Integer(stamp.to_millis() * NANOS_PER_MILLI));
        }
        if let Some(stamp) = query.end_time.as_ref() {
            parts.push(format!("timestamp {} ?", if backward { ">=" } else { "<=" }));
            values.push(Value::Integer(stamp.to_millis() * NANOS_PER_MILLI));
        }
        if let Some(id) = query.start_id.as_ref() {
            parts.push(format!("rowid {} ?", if backward { "<" } else { ">" }));
            values.push(Value::Integer(id.0));
        }
        if let Some(id) = query.end_id.as_ref() {
            parts.push(format!("rowid {} ?", if backward { ">" } else { "<" }));
            values.push(Value::Integer(id.0));
        }
        (parts.join(" and "), values)
    }

    fn insert_row(&self, item: &HistoryItem) -> Result<i64> {
        let timestamp = start_nanos(item).unwrap_or_else(now_nanos);
        let cwd = item.cwd.clone().unwrap_or_default();
        let hostname = item.hostname.clone().unwrap_or_default();
        if self.has_author_column {
            let author = std::env::var("USER").unwrap_or_default();
            self.db
                .execute(
                    "insert into history (id, timestamp, duration, exit, command, cwd, session, hostname, author) values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
                    params![
                        new_row_id(),
                        timestamp,
                        duration_nanos(item),
                        exit_value(item),
                        item.command_line,
                        cwd,
                        session_text(item),
                        hostname,
                        author
                    ],
                )
                .map_err(history_error)?;
        } else {
            self.db
                .execute(
                    "insert into history (id, timestamp, duration, exit, command, cwd, session, hostname) values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                    params![
                        new_row_id(),
                        timestamp,
                        duration_nanos(item),
                        exit_value(item),
                        item.command_line,
                        cwd,
                        session_text(item),
                        hostname
                    ],
                )
                .map_err(history_error)?;
        }
        Ok(self.db.last_insert_rowid())
    }

    fn write_row(&self, id: HistoryItemId, item: &HistoryItem) -> Result<()> {
        let changed = self
            .db
            .execute(
                "update history set timestamp = coalesce(?1, timestamp), duration = ?2, exit = ?3, command = ?4, cwd = ?5, session = ?6, hostname = ?7 where rowid = ?8",
                params![
                    start_nanos(item),
                    duration_nanos(item),
                    exit_value(item),
                    item.command_line,
                    item.cwd.clone().unwrap_or_default(),
                    session_text(item),
                    item.hostname.clone().unwrap_or_default(),
                    id.0
                ],
            )
            .map_err(history_error)?;
        if changed == 0 {
            return Err(history_error("Could not find item"));
        }
        Ok(())
    }
}

impl History for AiuBackedHistory {
    fn save(&mut self, mut item: HistoryItem) -> Result<HistoryItem> {
        match item.id {
            Some(id) => {
                self.write_row(id, &item)?;
                Ok(item)
            }
            None => {
                let rowid = self.insert_row(&item)?;
                item.id = Some(HistoryItemId::new(rowid));
                Ok(item)
            }
        }
    }

    fn load(&self, id: HistoryItemId) -> Result<HistoryItem> {
        self.db
            .query_row(
                "select rowid, timestamp, duration, exit, command, cwd, session, hostname from history where rowid = ?1",
                params![id.0],
                row_to_item,
            )
            .map_err(history_error)
    }

    fn count(&self, query: SearchQuery) -> Result<i64> {
        let (clause, values) = self.where_clause(&query);
        let sql = format!("select coalesce(count(*), 0) from history where {clause}");
        self.db
            .query_row(&sql, params_from_iter(values.iter()), |row| row.get(0))
            .map_err(history_error)
    }

    fn search(&self, query: SearchQuery) -> Result<Vec<HistoryItem>> {
        let (clause, mut values) = self.where_clause(&query);
        let order = if query.direction == SearchDirection::Backward {
            "desc"
        } else {
            "asc"
        };
        let mut sql = format!(
            "select rowid, timestamp, duration, exit, command, cwd, session, hostname from history where {clause} order by rowid {order}"
        );
        if let Some(limit) = query.limit {
            sql.push_str(" limit ?");
            values.push(Value::Integer(limit));
        }
        let mut statement = self.db.prepare(&sql).map_err(history_error)?;
        let rows = statement
            .query_map(params_from_iter(values.iter()), row_to_item)
            .map_err(history_error)?;
        rows.collect::<rusqlite::Result<Vec<HistoryItem>>>()
            .map_err(history_error)
    }

    fn update(
        &mut self,
        id: HistoryItemId,
        updater: &dyn Fn(HistoryItem) -> HistoryItem,
    ) -> Result<()> {
        let item = self.load(id)?;
        self.write_row(id, &updater(item))
    }

    fn clear(&mut self) -> Result<()> {
        self.db
            .execute("delete from history", params![])
            .map_err(history_error)?;
        Ok(())
    }

    fn delete(&mut self, id: HistoryItemId) -> Result<()> {
        let changed = self
            .db
            .execute("delete from history where rowid = ?1", params![id.0])
            .map_err(history_error)?;
        if changed == 0 {
            return Err(history_error("Could not find item"));
        }
        Ok(())
    }

    fn sync(&mut self) -> std::io::Result<()> {
        Ok(())
    }

    fn session(&self) -> Option<HistorySessionId> {
        self.session
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn memory_history() -> AiuBackedHistory {
        AiuBackedHistory::in_memory().unwrap()
    }

    fn save_command(history: &mut AiuBackedHistory, command: &str) -> HistoryItem {
        history.save(HistoryItem::from_command_line(command)).unwrap()
    }

    fn commands_newest_first(history: &AiuBackedHistory) -> Vec<String> {
        history
            .search(SearchQuery::everything(SearchDirection::Backward, None))
            .unwrap()
            .into_iter()
            .map(|item| item.command_line)
            .collect()
    }

    #[test]
    fn saved_commands_come_back_newest_first() {
        let mut history = memory_history();
        save_command(&mut history, "one");
        save_command(&mut history, "two");
        save_command(&mut history, "three");
        assert_eq!(commands_newest_first(&history), vec!["three", "two", "one"]);
    }

    #[test]
    fn prefix_search_finds_the_newest_matching_command() {
        let mut history = memory_history();
        save_command(&mut history, "cargo build");
        save_command(&mut history, "ls");
        save_command(&mut history, "cargo test");
        let found = history
            .search(SearchQuery::last_with_prefix(String::from("cargo"), None))
            .unwrap();
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].command_line, "cargo test");
    }

    #[test]
    fn substring_count_matches_only_containing_commands() {
        let mut history = memory_history();
        save_command(&mut history, "echo one");
        save_command(&mut history, "ls");
        save_command(&mut history, "echo two");
        let count = history
            .count(SearchQuery::all_that_contain_rev(String::from("echo")))
            .unwrap();
        assert_eq!(count, 2);
        assert_eq!(history.count_all().unwrap(), 3);
    }

    #[test]
    fn update_keeps_exit_status_and_duration() {
        let mut history = memory_history();
        let saved = save_command(&mut history, "sleep 1");
        let id = saved.id.unwrap();
        history
            .update(id, &|mut item| {
                item.exit_status = Some(3);
                item.duration = Some(Duration::from_millis(5));
                item.cwd = Some(String::from("/tmp"));
                item
            })
            .unwrap();
        let loaded = history.load(id).unwrap();
        assert_eq!(loaded.exit_status, Some(3));
        assert_eq!(loaded.duration, Some(Duration::from_millis(5)));
        assert_eq!(loaded.cwd, Some(String::from("/tmp")));
        assert_eq!(loaded.command_line, "sleep 1");
    }

    #[test]
    fn delete_and_clear_remove_commands() {
        let mut history = memory_history();
        let first = save_command(&mut history, "one");
        save_command(&mut history, "two");
        history.delete(first.id.unwrap()).unwrap();
        assert_eq!(commands_newest_first(&history), vec!["two"]);
        assert!(history.delete(first.id.unwrap()).is_err());
        history.clear().unwrap();
        assert_eq!(history.count_all().unwrap(), 0);
    }

    #[test]
    fn limit_and_id_bounds_walk_backward() {
        let mut history = memory_history();
        save_command(&mut history, "one");
        let second = save_command(&mut history, "two");
        save_command(&mut history, "three");
        let mut query = SearchQuery::everything(SearchDirection::Backward, None);
        query.start_id = second.id;
        query.limit = Some(1);
        let found = history.search(query).unwrap();
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].command_line, "one");
    }
}
