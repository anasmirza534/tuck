////  TODO: what happens when file content changed? like for text/docs files

import database.{init_database, insert_metadata, select_file}
import filepath
import gleam/bool
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import glugify
import input.{input}
import internal.{
  Metadata, get_day_str, get_ts, make_hash, print_metadata, ts_to_utc_string,
}
import simplifile
import sqlight

pub fn main() -> Nil {
  let res = sqlight.with_connection("tuck.db", run)

  case res {
    Ok(_) -> Nil
    Error(msg) -> {
      io.println_error(msg)
      halt(1)
    }
  }
}

fn run(conn: sqlight.Connection) -> Result(Nil, String) {
  use _ <- result.try(conn |> init_database())

  use _ <- result.try("test-20mb.bin" |> add_file(conn))

  Ok(Nil)
}

fn add_file(
  file_path: String,
  conn: sqlight.Connection,
) -> Result(Nil, String) {
  use path <- result.try(
    file_path
    |> absname()
    |> filepath.expand()
    |> result.replace_error("Invalid path: " <> file_path),
  )

  use exists <- result.try(
    path
    |> simplifile.is_file()
    |> result.replace_error("File permission issue, path: " <> path),
  )

  use <- bool.guard(
    when: exists |> bool.negate(),
    return: Error("Its not a file, path: " <> path),
  )

  use file_info <- result.try(
    path
    |> simplifile.file_info()
    |> result.replace_error("Could not get file info, path: " <> path),
  )

  use file_bits <- result.try(
    path
    |> simplifile.read_bits()
    |> result.replace_error("Could not read file, path" <> path),
  )

  let hash = file_bits |> make_hash()
  let hash_sliced = hash |> string.slice(0, 16)

  let name = path |> filepath.base_name()
  let name_without_ext =
    name
    |> filepath.strip_extension()
    |> glugify.slugify()
    |> string.slice(0, 16)
    |> string.remove_suffix("-")

  let ts = get_ts()
  let added_at = ts |> ts_to_utc_string()
  let date_str = get_day_str(ts)

  let stored_as =
    date_str
    <> "_"
    <> hash_sliced
    <> "_"
    <> name_without_ext
    <> {
      case filepath.extension(name) {
        Ok(ext) -> "." <> ext
        Error(_) -> ""
      }
    }

  let file_path_to = path |> filepath.directory_name |> filepath.join(stored_as)

  use db_files <- result.try(
    hash
    |> select_file(conn)
    |> result.map_error(fn(error) {
      "Error finding file in db, path: " <> path <> " , error: " <> error
    }),
  )

  let existing_orig_path =
    db_files
    |> list.map(fn(db_file) { db_file.orig_path })
    |> string.join("")

  use <- bool.guard(
    when: {
      db_files
      |> list.is_empty()
      |> bool.negate()
    },
    return: Error(
      "File already exists in db, path: "
      <> path
      <> " | original paths: "
      <> existing_orig_path,
    ),
  )

  let metadata = Metadata(hash, path, stored_as, file_info.size, added_at)
  metadata |> print_metadata()

  let user_answer =
    input("Do you want to add and rename to " <> file_path_to <> ": [y/N]: ")
    |> result.unwrap("n")
    |> string.lowercase()

  use <- bool.guard(
    when: user_answer != "y",
    return: Error("User rejected prompt"),
  )

  use _ <- result.try(
    metadata
    |> insert_metadata(conn)
    |> result.map_error(fn(error) {
      "Error inserting record in db, path: " <> path <> " , error: " <> error
    }),
  )

  use _ <- result.try(
    simplifile.rename(at: path, to: file_path_to)
    |> result.map_error(fn(error) {
      "Error renaming file: " <> simplifile.describe_error(error)
    }),
  )

  io.println("File added with hash: " <> metadata.hash)

  Ok(Nil)
}

@external(erlang, "filename", "absname")
fn absname(path: String) -> String

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil
