---
name: doctor
description: Read and act on doctor workflow reports to keep the store healthy.
---
## doctor

Doctor workflows run automatically on drain and publish to `artifacts.doctor.*`.

**Reading reports:**

```sh
textus get artifacts.doctor.manifest-files
```

Each report is a JSON file with:
- `ok` — boolean, false if issues found
- `issues` — array of `{code, severity, subject, message, fix}`
- `count` — number of issues

**Common fixes:**
- `manifest.missing_file` — create the entry with `textus put <key> --stdin --as=human`
- `sentinel.drift` — re-run `textus drain --as=automation`
- `schema_violation` — update the entry's front matter to match schema

**All doctor keys:**

```sh
textus list --lane=artifacts --prefix=artifacts.doctor
```
