# Tests

Runtime smoke tests live in:

```text
tests/runtime/
```

Use the layer README for details:

```text
tests/runtime/README.md
```

Quick commands:

```sh
cp tests/runtime/.env.example tests/runtime/.env
npm --prefix tests/runtime install
npm --prefix tests/runtime test
```

Static check:

```sh
npm --prefix tests/runtime run typecheck
```
