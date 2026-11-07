use crate::{
    PolarsPlugin,
    dataframe::values::NuSelector,
    values::{CustomValueSupport, PolarsPluginType},
};
use aiu_shell_plugin::{EngineInterface, EvaluatedCall, PluginCommand};
use aiu_shell_protocol::{Category, Example, LabeledError, PipelineData, Signature, Type};
use polars::prelude::Selector;

#[derive(Clone)]
pub struct SelectorEmpty;

impl PluginCommand for SelectorEmpty {
    type Plugin = PolarsPlugin;

    fn name(&self) -> &str {
        "polars selector empty"
    }

    fn description(&self) -> &str {
        "Create an empty selector that matches no columns. Useful as a base for selector composition."
    }

    fn signature(&self) -> Signature {
        Signature::build(self.name())
            .input_output_type(Type::Any, PolarsPluginType::NuSelector.into())
            .category(Category::Custom("expression".into()))
    }

    fn examples(&self) -> Vec<Example<'_>> {
        vec![Example {
            example: "polars selector empty",
            description: "Create an empty selector that matches no columns",
            result: None,
        }]
    }

    fn search_terms(&self) -> Vec<&str> {
        vec!["columns", "select", "empty", "none"]
    }

    fn run(
        &self,
        plugin: &Self::Plugin,
        engine: &EngineInterface,
        call: &EvaluatedCall,
        mut input: PipelineData,
    ) -> Result<PipelineData, LabeledError> {
        let metadata = input.take_metadata();

        let selector = Selector::Empty;
        let aiu_shell_selector = NuSelector::from(selector);

        aiu_shell_selector
            .to_pipeline_data(plugin, engine, call.head)
            .map_err(LabeledError::from)
            .map(|pd| pd.set_metadata(metadata))
    }
}

#[cfg(test)]
mod test {
    use super::*;
    use crate::test::test_polars_plugin_command;

    #[test]
    fn test_examples() -> Result<(), aiu_shell_protocol::ShellError> {
        test_polars_plugin_command(&SelectorEmpty)
    }
}
