///|
fn ssa_variable_names_json(
  program : FlowProgram,
  indices : Array[Int32],
) -> Json {
  let ordered = indices.copy()
  ordered.sort()
  Json::array(
    ordered.map(variable => Json::string(program.variables[variable])),
  )
}

///|
/// Internal serializer for a fresh, valid plan produced by plan_ssa.
fn ssa_plan_json_value(plan : SsaPlan) -> Json {
  let program = plan.program
  let graph = program.graph
  let phi_variables : Array[Array[Int32]] = Array::makei(graph.nodes.length(), _ => {
    []
  })
  let entry_values_required = []
  for placement in plan.placements {
    for node in placement.phi_nodes {
      phi_variables[node].push(placement.variable)
    }
    if placement.requires_entry_value {
      entry_values_required.push(
        Json::string(program.variables[placement.variable]),
      )
    }
  }
  let blocks = []
  for node, name in graph.nodes {
    blocks.push(
      Json::object(
        Map([
          ("id", Json::string(name)),
          ("reachable", Json::boolean(plan.liveness.reachable[node])),
          (
            "defines",
            ssa_variable_names_json(program, program.definitions[node]),
          ),
          ("uses", ssa_variable_names_json(program, program.uses[node])),
          (
            "live_in",
            ssa_variable_names_json(program, plan.liveness.live_in[node]),
          ),
          (
            "live_out",
            ssa_variable_names_json(program, plan.liveness.live_out[node]),
          ),
          (
            "phi_variables",
            ssa_variable_names_json(program, phi_variables[node]),
          ),
        ]),
      ),
    )
  }
  let placements = plan.placements.map(placement => {
    Json::object(
      Map([
        ("variable", Json::string(program.variables[placement.variable])),
        ("definition_blocks", names_json(graph, placement.definitions)),
        ("live_in_blocks", names_json(graph, placement.live_in)),
        ("phi_blocks", names_json(graph, placement.phi_nodes)),
        ("requires_entry_value", Json::boolean(placement.requires_entry_value)),
      ]),
    )
  })
  Json::object(
    Map([
      ("schema", Json::string("cairndom.ssa-plan.v1")),
      ("entry", Json::string(graph.nodes[graph.entry])),
      ("scope", Json::string("entry_reachable_all_paths")),
      ("use_convention", Json::string("before_local_definition")),
      ("status", Json::string("locations_only")),
      (
        "variables",
        Json::array(program.variables.map(name => Json::string(name))),
      ),
      ("blocks", Json::array(blocks)),
      ("placements", Json::array(placements)),
      ("entry_values_required", Json::array(entry_values_required)),
      (
        "entry_value_semantics",
        Json::string(
          "Variables live before entry local definitions require a caller-supplied parameter or initial value, or a missing-initialization diagnostic under the source language's rules.",
        ),
      ),
    ]),
  )
}

///|
/// Compute a fresh plan and serialize cairndom.ssa-plan.v1 using original IDs.
/// The report contains phi locations and entry-value requirements, without IR
/// rewriting or variable renaming. Unreachable input facts remain visible but
/// contribute no liveness or placement results. Output is limited to 16 MiB.
pub fn ssa_plan_json_text(program : FlowProgram) -> String raise GraphError {
  prepare_ssa(program).json_text()
}

///|
// Requires the privately owned result of a fresh, valid plan_ssa computation.
fn bounded_ssa_plan_json_text(plan : SsaPlan) -> String raise GraphError {
  let output = ssa_plan_json_value(plan).stringify(indent=2)
  if output.length() > 16_777_216 {
    raise Invalid("SSA plan JSON exceeds 16 MiB")
  }
  output
}
