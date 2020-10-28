# libguestfs bindings for Rust

This package contains the libguestfs bindings for Rust. You can use this crate
by using cargo. See [crates.io](https://crates.io/crates/guestfs)

# For maintainer

## How to test

Tests are incorporated into the build system.

You can test it manually by

```
$ ../run cargo test
```

## How to publish

### 1. Fix version in Cargo.toml.in

Regarding Versioning convention, see [Semantic
Versioning](https://semver.org/).

You must not break '-compat@VERSION@' to make sure that this binding is
compatible with the installed libguestfs.

Example
```
version = "0.1.0-compat@VERSION@"
```

### 2. Commit the change of the version

### 3. Build libguestfs

### 4. Publish

```
$ cargo publish
```

