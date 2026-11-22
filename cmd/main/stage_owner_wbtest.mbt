///|
test "stage activity requires a matching scope and a confirmed process identity" {
  let owner : StageOwner = {
    task: "task",
    output: "report.json",
    pid: 21,
    scope: "local",
    started: "100",
  }
  inspect(stage_activity(owner, "local", "100"), content="active")
  inspect(stage_activity(owner, "local", "200"), content="abandoned")
  inspect(stage_activity(owner, "local", "dead"), content="abandoned")
  inspect(stage_activity(owner, "local", ""), content="unknown")
  inspect(stage_activity(owner, "local", "denied"), content="unknown")
  inspect(stage_activity(owner, "foreign", "100"), content="unknown")
  inspect(stage_activity(owner, "foreign", "dead"), content="unknown")
}
