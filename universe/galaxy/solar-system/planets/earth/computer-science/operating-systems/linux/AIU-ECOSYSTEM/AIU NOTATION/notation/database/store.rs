use std::collections::BTreeMap;

use crate::database_record::Record;

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Store {
    records: BTreeMap<(String, String), Record>,
}

impl Store {
    pub fn new() -> Store {
        Store::default()
    }

    pub fn len(&self) -> usize {
        self.records.len()
    }

    pub fn is_empty(&self) -> bool {
        self.records.is_empty()
    }

    pub fn put(&mut self, record: Record) -> Option<Record> {
        self.records
            .insert((record.kind.clone(), record.key.clone()), record)
    }

    pub fn get(&self, kind: &str, key: &str) -> Option<&Record> {
        self.records.get(&(kind.to_string(), key.to_string()))
    }

    pub fn remove(&mut self, kind: &str, key: &str) -> Option<Record> {
        self.records.remove(&(kind.to_string(), key.to_string()))
    }

    pub fn all(&self) -> Vec<&Record> {
        self.records.values().collect()
    }

    pub fn of_kind(&self, kind: &str) -> Vec<&Record> {
        self.records.values().filter(|r| r.kind == kind).collect()
    }

    pub fn from_source(&self, source: &str) -> Vec<&Record> {
        self.records
            .values()
            .filter(|r| r.source == source)
            .collect()
    }

    pub fn drop_source(&mut self, source: &str) -> usize {
        let before = self.records.len();
        self.records.retain(|_, r| r.source != source);
        before - self.records.len()
    }

    pub fn replace_source(
        &mut self,
        source: &str,
        kind: &str,
        records: Vec<Record>,
    ) -> Result<(), String> {
        for r in &records {
            if r.source != source || r.kind != kind {
                return Err(format!(
                    "record {} {} of {} does not belong to kind {} of {}",
                    r.kind, r.key, r.source, kind, source
                ));
            }
        }
        self.records
            .retain(|_, r| !(r.source == source && r.kind == kind));
        for r in records {
            self.put(r);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn block(kind: &str, key: &str, source: &str) -> Record {
        Record::new(kind, key, source).with_field("name", key)
    }

    #[test]
    fn put_replaces_the_record_with_the_same_kind_and_key() {
        let mut store = Store::new();
        assert!(store.put(block("block", "a", "one.aiu")).is_none());
        assert!(store.put(block("block", "a", "two.aiu")).is_some());
        assert_eq!(store.len(), 1);
        assert_eq!(store.get("block", "a").unwrap().source, "two.aiu");
    }

    #[test]
    fn replace_source_swaps_only_that_source_and_kind() {
        let mut store = Store::new();
        store.put(block("block", "a", "one.aiu"));
        store.put(block("tag", "t", "one.aiu"));
        store.put(block("block", "b", "two.aiu"));
        let fresh = vec![block("block", "c", "one.aiu")];
        store.replace_source("one.aiu", "block", fresh).unwrap();
        assert!(store.get("block", "a").is_none());
        assert!(store.get("block", "c").is_some());
        assert!(store.get("tag", "t").is_some());
        assert!(store.get("block", "b").is_some());
    }

    #[test]
    fn replace_source_refuses_a_record_of_another_source() {
        let mut store = Store::new();
        store.put(block("block", "a", "one.aiu"));
        let wrong = vec![block("block", "z", "two.aiu")];
        assert!(store.replace_source("one.aiu", "block", wrong).is_err());
        assert!(store.get("block", "a").is_some());
        assert!(store.get("block", "z").is_none());
    }

    #[test]
    fn drop_source_removes_every_kind_of_that_source() {
        let mut store = Store::new();
        store.put(block("block", "a", "one.aiu"));
        store.put(block("tag", "t", "one.aiu"));
        store.put(block("block", "b", "two.aiu"));
        assert_eq!(store.drop_source("one.aiu"), 2);
        assert_eq!(store.len(), 1);
        assert_eq!(store.of_kind("block").len(), 1);
        assert_eq!(store.from_source("two.aiu").len(), 1);
    }
}
