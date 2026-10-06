# tuck

CLI based application for renaming files and storing thier metadata.

## Install

Requires [Gleam](https://gleam.run) and Erlang (e.g. via [mise](https://mise.jdx.dev)),
plus `rebar3` (needed to build `sqlight`'s native SQLite driver):

```sh
mise use -g erlang gleam rebar
```

Then build a standalone copy that doesn't need recompiling to run:

```sh
git clone https://github.com/anasmirza534/tuck.git
cd tuck
gleam export erlang-shipment
```

Put a `tuck` command on your `PATH` (adjust the path to where you cloned it):

```sh
cat > ~/.local/bin/tuck << 'EOF'
#!/bin/sh
exec /path/to/tuck/build/erlang-shipment/entrypoint.sh run "$@"
EOF
chmod +x ~/.local/bin/tuck
```

Now `tuck help` works from any directory. Metadata is stored in
`~/.local/share/tuck/tuck.db`.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

Changes to the source don't affect the exported `tuck` command above until
you re-run `gleam export erlang-shipment`.
