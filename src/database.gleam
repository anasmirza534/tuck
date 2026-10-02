import gleam/dynamic/decode
import gleam/result
import internal.{type Metadata, Metadata}
import sqlight

fn file_decoder() -> decode.Decoder(Metadata) {
  use hash <- decode.field(0, decode.string)
  use orig_path <- decode.field(1, decode.string)
  use stored_as <- decode.field(2, decode.string)
  use file_size <- decode.field(3, decode.int)
  use added_at <- decode.field(4, decode.string)

  decode.success(Metadata(hash, orig_path, stored_as, file_size, added_at))
}

pub fn init_database(conn: sqlight.Connection) -> Result(Nil, String) {
  let sql =
    "CREATE TABLE IF NOT EXISTS files (
      hash         TEXT PRIMARY KEY,
      orig_path    TEXT NOT NULL,
      stored_as    TEXT NOT NULL,
      file_size    INTEGER NOT NULL,
      added_at     TEXT NOT NULL
    );"

  use _ <- result.try(
    sql
    |> sqlight.exec(conn)
    |> result.map_error(fn(error) { error.message }),
  )

  Ok(Nil)
}

pub fn select_file_by_hash(
  hash: String,
  conn: sqlight.Connection,
) -> Result(List(Metadata), String) {
  let sql = "SELECT * FROM files WHERE hash = ?;"

  sqlight.query(
    sql,
    on: conn,
    with: [sqlight.text(hash)],
    expecting: file_decoder(),
  )
  |> result.map_error(fn(error) { error.message })
}

pub fn select_file_by_trunced_hash(
  hash: String,
  conn: sqlight.Connection,
) -> Result(List(Metadata), String) {
  let sql = "SELECT * FROM files WHERE hash LIKE ?;"

  sqlight.query(
    sql,
    on: conn,
    with: [sqlight.text(hash <> "%")],
    expecting: file_decoder(),
  )
  |> result.map_error(fn(error) { error.message })
}

pub fn select_files(
  conn: sqlight.Connection,
) -> Result(List(Metadata), String) {
  let sql = "SELECT * FROM files;"

  sql
  |> sqlight.query(on: conn, with: [], expecting: file_decoder())
  |> result.map_error(fn(error) { error.message })
}

pub fn insert_metadata(
  metadata: Metadata,
  conn: sqlight.Connection,
) -> Result(Nil, String) {
  let sql =
    "INSERT INTO files (hash, orig_path, stored_as, file_size, added_at)
  VALUES (?, ?, ?, ?, ?)"

  sql
  |> sqlight.query(
    on: conn,
    with: [
      sqlight.text(metadata.hash),
      sqlight.text(metadata.orig_path),
      sqlight.text(metadata.stored_as),
      sqlight.int(metadata.file_size),
      sqlight.text(metadata.added_at),
    ],
    expecting: decode.success(Nil),
  )
  |> result.replace(Nil)
  |> result.map_error(fn(error) { error.message })
}
