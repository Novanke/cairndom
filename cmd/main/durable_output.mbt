///|
extern "js" fn IoResult::published(self : Self) -> Bool =
  #| result => result.published

///|
extern "js" fn IoResult::directory_synced(self : Self) -> Bool =
  #| result => result.directorySynced

///|
extern "js" fn IoResult::stage_created(self : Self) -> Bool =
  #| result => result.stageCreated

///|
extern "js" fn IoResult::stage_cleaned(self : Self) -> Bool =
  #| result => result.stageCleaned

///|
extern "js" fn IoResult::output_path(self : Self) -> String =
  #| result => result.outputPath

///|
extern "js" fn IoResult::stage_path(self : Self) -> String =
  #| result => result.stagePath

///|
extern "js" fn IoResult::sync_error(self : Self) -> String =
  #| result => result.syncError

///|
extern "js" fn IoResult::cleanup_error(self : Self) -> String =
  #| result => result.cleanupError

///|
fn optional_text(value : String) -> Json {
  if value == "" {
    Json::null()
  } else {
    Json::string(value)
  }
}

///|
fn write_durable_output(
  path : String,
  text : String,
) -> Unit raise CommandError {
  let result = file_io("write-durable", path, text, _ => ())
  let published = result.published()
  let directory_synced = result.directory_synced()
  let stage_created = result.stage_created()
  let stage_cleaned = result.stage_cleaned()
  let publication_error = result.error()
  let sync_error = result.sync_error()
  let cleanup_error = result.cleanup_error()
  if !(published && directory_synced && stage_cleaned) ||
    publication_error != "" ||
    sync_error != "" ||
    cleanup_error != "" {
    set_exit_code(2)
  }
  let receipt = Json::object(
    Map([
      ("schema", Json::string("cairndom.durable-output.v1")),
      ("output", Json::string(result.output_path())),
      ("published", Json::boolean(published)),
      ("directory_synced", Json::boolean(directory_synced)),
      ("stage_created", Json::boolean(stage_created)),
      ("stage_cleaned", Json::boolean(stage_cleaned)),
      ("stage_path", optional_text(result.stage_path())),
      ("publication_error", optional_text(publication_error)),
      ("sync_error", optional_text(sync_error)),
      ("cleanup_error", optional_text(cleanup_error)),
    ]),
  )
  ignore(io("stdout", "", text=receipt.stringify(indent=2) + "\n"))
}
