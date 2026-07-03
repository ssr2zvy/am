const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .musl,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "am",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Shared dependency root for vendored C libraries (e.g. SQLite, llama.cpp,
    // future deps). upaupa/ contains all external dependencies copied in by
    // container setup.
    //   upaupa/sqlite/src/  - sqlite3.c/h/ext.h (vendored sqlite amalgamation)
    //   upaupa/llama/src/   - llama.cpp + ggml sources
    //   upaupa/llama/include/ - llama.h + supporting headers
    const upaupa_dir = "upaupa";
    const upa_sqlite_dir = b.path(upaupa_dir ++ "/sqlite/src");
    const upa_llama_src_dir = b.path(upaupa_dir ++ "/llama/src");
    const upa_llama_include_dir = b.path(upaupa_dir ++ "/llama/include");
    
    // Build sqlite3 as a static library from vendored source
    const sqlite3_lib = b.addStaticLibrary(.{
        .name = "sqlite3",
        .target = target,
        .optimize = optimize,
    });
    sqlite3_lib.addCSourceFile(.{
        .file = b.path("upaupa/sqlite/src/sqlite3.c"),
        .flags = &.{
            "-DSQLITE_OMIT_LOAD_EXTENSION",
        },
    });
    sqlite3_lib.linkLibC();
    
    // Link the static sqlite3 library into am
    exe.linkLibrary(sqlite3_lib);
    exe.addIncludePath(upa_sqlite_dir);
    exe.linkLibC();

    // Build llama.cpp + ggml as a static library from vendored source.
    // The directory layout mirrors b8146 (CPU-only, GPU backends stripped
    // by the Containerfile). `upa-code-dependencies.sh` populates the
    // upaupa/llama/ tree from the container image on first start.
    //
    // Directory layout after sync:
    //   upaupa/llama/include/   ← top-level headers (llama.h, llama-cpp.h)
    //   upaupa/llama/src/       ← llama core (llama-*.cpp, models/*.cpp, unicode)
    //   upaupa/llama/ggml/      ← ggml tree (include/, src/, src/ggml-cpu/)
    const upa_llama_ggml_include_dir = b.path(upaupa_dir ++ "/llama/ggml/include");
    const upa_llama_ggml_src_dir = b.path(upaupa_dir ++ "/llama/ggml/src");
    const upa_llama_ggml_cpu_dir = b.path(upaupa_dir ++ "/llama/ggml/src/ggml-cpu");

    const llama_lib = b.addStaticLibrary(.{
        .name = "llama",
        .target = target,
        .optimize = optimize,
    });
    const llama_c_flags = &.{
        "-DGGML_USE_CPU",
        "-D_GNU_SOURCE",
        "-DNDEBUG",
        "-DGGML_VERSION=0",
        "-DGGML_COMMIT=\"\"",
        "-O3",
        "-pthread",
        "-fno-sanitize=undefined",
    };
    const llama_cpp_flags = &.{
        "-DGGML_USE_CPU",
        "-D_GNU_SOURCE",
        "-DNDEBUG",
        "-DGGML_VERSION=0",
        "-DGGML_COMMIT=\"\"",
        "-O3",
        "-pthread",
        "-std=c++17",
        "-fno-sanitize=undefined",
    };

    // --- ggml core C sources (ggml/src/) ---
    llama_lib.addCSourceFiles(.{
        .root = upa_llama_ggml_src_dir,
        .files = &.{
            "ggml.c",
            "ggml-alloc.c",
            "ggml-quants.c",
        },
        .flags = llama_c_flags,
    });
    // --- ggml core C++ sources (ggml/src/) ---
    llama_lib.addCSourceFiles(.{
        .root = upa_llama_ggml_src_dir,
        .files = &.{
            "ggml.cpp",
            "ggml-backend.cpp",
            "ggml-backend-dl.cpp",
            "ggml-backend-reg.cpp",
            "ggml-opt.cpp",
            "ggml-threading.cpp",
            "gguf.cpp",
        },
        .flags = llama_cpp_flags,
    });
    // --- ggml CPU backend (ggml/src/ggml-cpu/) ---
    llama_lib.addCSourceFiles(.{
        .root = upa_llama_ggml_cpu_dir,
        .files = &.{
            "ggml-cpu.c",
            "ggml-cpu.cpp",
            "quants.c",
            "arch/x86/quants.c",
        },
        .flags = llama_c_flags,
    });
    llama_lib.addCSourceFiles(.{
        .root = upa_llama_ggml_cpu_dir,
        .files = &.{
            "ops.cpp",
            "binary-ops.cpp",
            "unary-ops.cpp",
            "vec.cpp",
            "traits.cpp",
            "hbm.cpp",
            "repack.cpp",
            "arch/x86/cpu-feats.cpp",
            "arch/x86/repack.cpp",
            "amx/amx.cpp",
            "amx/mmq.cpp",
            "llamafile/sgemm.cpp",
        },
        .flags = llama_cpp_flags,
    });

    // --- llama.cpp core C++ sources (src/) ---
    llama_lib.addCSourceFiles(.{
        .root = upa_llama_src_dir,
        .files = &.{
            "llama.cpp",
            "llama-adapter.cpp",
            "llama-arch.cpp",
            "llama-batch.cpp",
            "llama-chat.cpp",
            "llama-context.cpp",
            "llama-cparams.cpp",
            "llama-grammar.cpp",
            "llama-graph.cpp",
            "llama-hparams.cpp",
            "llama-impl.cpp",
            "llama-io.cpp",
            "llama-kv-cache.cpp",
            "llama-kv-cache-iswa.cpp",
            "llama-memory.cpp",
            "llama-memory-hybrid.cpp",
            "llama-memory-hybrid-iswa.cpp",
            "llama-memory-recurrent.cpp",
            "llama-mmap.cpp",
            "llama-model.cpp",
            "llama-model-loader.cpp",
            "llama-model-saver.cpp",
            "llama-quant.cpp",
            "llama-sampler.cpp",
            "llama-vocab.cpp",
            "unicode.cpp",
            "unicode-data.cpp",
        },
        .flags = llama_cpp_flags,
    });
    // --- model architecture implementations (src/models/) ---
    // Every .cpp in src/models/ registers a model arch. Including all of
    // them so any GGUF the user drops in works out of the box. If binary
    // size matters, trim this list to only the arches you ship GGUFs for.
    llama_lib.addCSourceFiles(.{
        .root = upa_llama_src_dir,
        .files = &.{
            "models/llama.cpp",
            "models/phi3.cpp",
            "models/qwen.cpp",
            "models/qwen2.cpp",
            "models/qwen3.cpp",
            "models/qwen35.cpp",
            "models/gemma.cpp",
            "models/gemma2-iswa.cpp",
            "models/gemma3.cpp",
            "models/gpt2.cpp",
            "models/gptneox.cpp",
            "models/bert.cpp",
            "models/bloom.cpp",
            "models/falcon.cpp",
            "models/starcoder.cpp",
            "models/starcoder2.cpp",
            "models/deepseek.cpp",
            "models/deepseek2.cpp",
            "models/chatglm.cpp",
            "models/glm4.cpp",
            "models/mamba.cpp",
            "models/mamba-base.cpp",
            "models/granite.cpp",
            "models/granite-hybrid.cpp",
            "models/minicpm3.cpp",
            "models/rwkv6.cpp",
            "models/rwkv6-base.cpp",
            "models/rwkv7.cpp",
            "models/rwkv7-base.cpp",
            "models/internlm2.cpp",
            "models/command-r.cpp",
            "models/olmo.cpp",
            "models/olmo2.cpp",
            "models/olmoe.cpp",
            "models/phi2.cpp",
            "models/plamo.cpp",
            "models/stablelm.cpp",
            "models/baichuan.cpp",
            "models/jais.cpp",
            "models/jais2.cpp",
            "models/codeshell.cpp",
            "models/orion.cpp",
            "models/nemotron.cpp",
            "models/exaone.cpp",
            "models/exaone4.cpp",
            "models/t5-enc.cpp",
            "models/t5-dec.cpp",
            "models/jamba.cpp",
            "models/mpt.cpp",
            "models/refact.cpp",
            "models/dbrx.cpp",
            "models/openelm.cpp",
            "models/bitnet.cpp",
            "models/grok.cpp",
            "models/deci.cpp",
            "models/arctic.cpp",
            "models/chameleon.cpp",
            "models/wavtokenizer-dec.cpp",
            "models/xverse.cpp",
            "models/modern-bert.cpp",
            "models/neo-bert.cpp",
            "models/plamo2.cpp",
            "models/plamo3.cpp",
            "models/dream.cpp",
            "models/mistral3.cpp",
            "models/cogvlm.cpp",
            "models/qwen2moe.cpp",
            "models/qwen3moe.cpp",
            "models/qwen35moe.cpp",
            "models/qwen2vl.cpp",
            "models/qwen3vl.cpp",
            "models/qwen3vl-moe.cpp",
            "models/qwen3next.cpp",
            "models/falcon-h1.cpp",
            "models/nemotron-h.cpp",
            "models/smallthinker.cpp",
            "models/smollm3.cpp",
            "models/cohere2-iswa.cpp",
            "models/llama-iswa.cpp",
            "models/minimax-m2.cpp",
            "models/mimo2-iswa.cpp",
            "models/hunyuan-dense.cpp",
            "models/hunyuan-moe.cpp",
            "models/glm4-moe.cpp",
            "models/bailingmoe.cpp",
            "models/bailingmoe2.cpp",
            "models/ernie4-5.cpp",
            "models/ernie4-5-moe.cpp",
            "models/dots1.cpp",
            "models/arcee.cpp",
            "models/seed-oss.cpp",
            "models/rnd1.cpp",
            "models/step35-iswa.cpp",
            "models/kimi-linear.cpp",
            "models/exaone-moe.cpp",
            "models/delta-net-base.cpp",
            "models/arwkv7.cpp",
            "models/rwkv6qwen2.cpp",
            "models/openai-moe-iswa.cpp",
            "models/gemma3n-iswa.cpp",
            "models/lfm2.cpp",
            "models/llada.cpp",
            "models/llada-moe.cpp",
            "models/afmoe.cpp",
            "models/apertus.cpp",
            "models/maincoder.cpp",
            "models/grovemoe.cpp",
            "models/plm.cpp",
            "models/paddleocr.cpp",
            "models/pangu-embedded.cpp",
            "models/gemma-embedding.cpp",
        },
        .flags = llama_cpp_flags,
    });

    // Include paths: llama headers + ggml headers + ggml source internals
    // (some ggml .c files include sibling .h files via relative paths).
    llama_lib.addIncludePath(upa_llama_include_dir);
    llama_lib.addIncludePath(upa_llama_src_dir);
    llama_lib.addIncludePath(upa_llama_ggml_include_dir);
    llama_lib.addIncludePath(upa_llama_ggml_src_dir);
    llama_lib.addIncludePath(upa_llama_ggml_cpu_dir);
    llama_lib.linkLibC();
    llama_lib.linkLibCpp();

    // Link llama into am and expose its headers to the FFI module.
    exe.linkLibrary(llama_lib);
    exe.addIncludePath(upa_llama_include_dir);
    exe.addIncludePath(upa_llama_ggml_include_dir);
    exe.linkLibCpp();

    // Add gterminal module
    const gterminal_mod = b.addModule("gterminal", .{
        .root_source_file = b.path("src/gterminal/g.zig"),
    });
    exe.root_module.addImport("gterminal", gterminal_mod);

    // Add gid module (glog manager)
    const gid_mod = b.addModule("gid", .{
        .root_source_file = b.path("src/upa/gid/g.zig"),
    });
    exe.root_module.addImport("gid", gid_mod);

    // Add getLocation module (path helper)
    const getlocation_mod = b.addModule("getLocation", .{
        .root_source_file = b.path("src/upa/getLocation/g.zig"),
    });
    exe.root_module.addImport("getLocation", getlocation_mod);

    // Add topRight module (needs gterminal)
    const topright_mod = b.addModule("topRight", .{
        .root_source_file = b.path("src/upa/topRight/g.zig"),
    });
    topright_mod.addImport("gterminal", gterminal_mod);
    exe.root_module.addImport("topRight", topright_mod);

    // Add sqlite module (shared DB layer)
    const sqlite_mod = b.addModule("sqlite", .{
        .root_source_file = b.path("src/upa/sqlite/g.zig"),
    });
    sqlite_mod.addIncludePath(upa_sqlite_dir);
    sqlite_mod.linkLibrary(sqlite3_lib);
    sqlite_mod.addImport("getLocation", getlocation_mod);
    exe.root_module.addImport("sqlite", sqlite_mod);

    // Add handleEvent module (depends on sqlite)
    const handleevent_mod = b.addModule("handleEvent", .{
        .root_source_file = b.path("src/upa/handleEvent/g.zig"),
    });
    handleevent_mod.addImport("sqlite", sqlite_mod);
    exe.root_module.addImport("handleEvent", handleevent_mod);

    // Wire handleEvent back into sqlite (circular dependency for types)
    sqlite_mod.addImport("handleEvent", handleevent_mod);

    // Add errors module (centralized error reporting, separate from sqlite)
    const errors_mod = b.addModule("errors", .{
        .root_source_file = b.path("src/upa/errors/g.zig"),
    });
    errors_mod.addImport("getLocation", getlocation_mod);
    exe.root_module.addImport("errors", errors_mod);

    // Add session module (session lifecycle, depends on sqlite, errors)
    const session_mod = b.addModule("session", .{
        .root_source_file = b.path("src/upa/session/g.zig"),
    });
    session_mod.addImport("sqlite", sqlite_mod);
    session_mod.addImport("errors", errors_mod);
    exe.root_module.addImport("session", session_mod);

    // Add trace module (raw ANSI/key logging, depends on sqlite, errors, session, gterminal)
    const trace_mod = b.addModule("trace", .{
        .root_source_file = b.path("src/upa/trace/g.zig"),
    });
    trace_mod.addImport("sqlite", sqlite_mod);
    trace_mod.addImport("errors", errors_mod);
    trace_mod.addImport("session", session_mod);
    trace_mod.addImport("gterminal", gterminal_mod);
    exe.root_module.addImport("trace", trace_mod);

    // Add snapshot module (cell grid snapshots, depends on sqlite, errors, session)
    const snapshot_mod = b.addModule("snapshot", .{
        .root_source_file = b.path("src/upa/snapshot/g.zig"),
    });
    snapshot_mod.addImport("sqlite", sqlite_mod);
    snapshot_mod.addImport("errors", errors_mod);
    snapshot_mod.addImport("session", session_mod);
    exe.root_module.addImport("snapshot", snapshot_mod);

    // Wire trace and snapshot into gterminal for direct calls
    gterminal_mod.addImport("trace", trace_mod);
    gterminal_mod.addImport("snapshot", snapshot_mod);

    // Add gstage module (needs gterminal, gid, topRight, handleEvent, errors, session)
    const gstage_mod = b.addModule("gstage", .{
        .root_source_file = b.path("src/gstage/g.zig"),
    });
    gstage_mod.addImport("gterminal", gterminal_mod);
    gstage_mod.addImport("gid", gid_mod);
    gstage_mod.addImport("topRight", topright_mod);
    gstage_mod.addImport("handleEvent", handleevent_mod);
    gstage_mod.addImport("errors", errors_mod);
    gstage_mod.addImport("session", session_mod);
    exe.root_module.addImport("gstage", gstage_mod);

    // Standalone gtext parser module (no TUI/sqlite deps) — used by both
    // interactive gtext and CLI non-interactive validation.
    const gtext_parser_mod = b.addModule("gtext_parser", .{
        .root_source_file = b.path("src/gtext/parser/g.zig"),
    });

    // Add gtext module (needs gterminal, topRight, sqlite, handleEvent, errors, session, gtext_parser)
    const gtext_mod = b.addModule("gtext", .{
        .root_source_file = b.path("src/gtext/g.zig"),
    });
    gtext_mod.addImport("gterminal", gterminal_mod);
    gtext_mod.addImport("topRight", topright_mod);
    gtext_mod.addImport("sqlite", sqlite_mod);
    gtext_mod.addImport("handleEvent", handleevent_mod);
    gtext_mod.addImport("errors", errors_mod);
    gtext_mod.addImport("session", session_mod);
    gtext_mod.addImport("gtext_parser", gtext_parser_mod);
    exe.root_module.addImport("gtext", gtext_mod);

    // Wire sqlite into gid module
    gid_mod.addImport("sqlite", sqlite_mod);

    // Add llama module (thin Zig wrapper around the embedded llama.cpp runtime).
    // Used by the `am flow` CLI command for single-shot LLM queries.
    const llama_mod = b.addModule("llama", .{
        .root_source_file = b.path("src/upa/llama/g.zig"),
    });
    llama_mod.addIncludePath(upa_llama_include_dir);
    llama_mod.addIncludePath(upa_llama_ggml_include_dir);
    llama_mod.linkLibrary(llama_lib);
    exe.root_module.addImport("llama", llama_mod);


    // Add cli module (argv dispatcher, help text, version constant)
    const cli_mod = b.addModule("cli", .{
        .root_source_file = b.path("src/cli/dispatch.zig"),
    });
    cli_mod.addImport("sqlite", sqlite_mod);
    cli_mod.addImport("gtext_parser", gtext_parser_mod);
    cli_mod.addImport("llama", llama_mod);
    exe.root_module.addImport("cli", cli_mod);

    b.installArtifact(exe);

    // amconfig executable (installer)
    const amconfig_exe = b.addExecutable(.{
        .name = "amconfig",
        .root_source_file = b.path("src/amconfig_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(amconfig_exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the am application");
    run_step.dependOn(&run_cmd.step);

    // Tests for main
    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_tests.root_module.addImport("gterminal", gterminal_mod);
    main_tests.root_module.addImport("gid", gid_mod);
    main_tests.root_module.addImport("getLocation", getlocation_mod);
    main_tests.root_module.addImport("gstage", gstage_mod);
    main_tests.root_module.addImport("topRight", topright_mod);
    main_tests.root_module.addImport("gtext", gtext_mod);
    main_tests.root_module.addImport("sqlite", sqlite_mod);
    main_tests.root_module.addImport("handleEvent", handleevent_mod);
    main_tests.root_module.addImport("session", session_mod);
    main_tests.root_module.addImport("trace", trace_mod);
    main_tests.root_module.addImport("snapshot", snapshot_mod);
    main_tests.root_module.addImport("cli", cli_mod);

    // Tests for cli/dispatch.zig
    const cli_tests = b.addTest(.{
        .root_source_file = b.path("src/cli/dispatch.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_tests.root_module.addImport("sqlite", sqlite_mod);
    cli_tests.root_module.addImport("gtext_parser", gtext_parser_mod);
    cli_tests.root_module.addImport("llama", llama_mod);

    // Tests for gid module
    const gid_tests = b.addTest(.{
        .root_source_file = b.path("src/upa/gid/g.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Tests for gstage types (self-contained)
    // Note: gstage/g.zig is tested transitively through main.zig
    const gstage_types_tests = b.addTest(.{
        .root_source_file = b.path("src/gstage/types.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Tests for shared gterminal module
    const gterminal_keys_tests = b.addTest(.{
        .root_source_file = b.path("src/gterminal/keys.zig"),
        .target = target,
        .optimize = optimize,
    });

    const gterminal_screen_tests = b.addTest(.{
        .root_source_file = b.path("src/gterminal/screen.zig"),
        .target = target,
        .optimize = optimize,
    });

    const gterminal_rawmode_tests = b.addTest(.{
        .root_source_file = b.path("src/gterminal/raw_mode.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Tests for topRight module
    const topright_chars_tests = b.addTest(.{
        .root_source_file = b.path("src/upa/topRight/utils/chars.zig"),
        .target = target,
        .optimize = optimize,
    });

    const topright_types_tests = b.addTest(.{
        .root_source_file = b.path("src/upa/topRight/types.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Tests for handleEvent are covered transitively through main_tests
    // (handleEvent/time/state.zig tests run when handleEvent module is used)

    const run_main_tests = b.addRunArtifact(main_tests);
    const run_gid_tests = b.addRunArtifact(gid_tests);
    const run_gstage_types_tests = b.addRunArtifact(gstage_types_tests);
    const run_gterminal_keys_tests = b.addRunArtifact(gterminal_keys_tests);
    const run_gterminal_screen_tests = b.addRunArtifact(gterminal_screen_tests);
    const run_gterminal_rawmode_tests = b.addRunArtifact(gterminal_rawmode_tests);
    const run_topright_chars_tests = b.addRunArtifact(topright_chars_tests);
    const run_topright_types_tests = b.addRunArtifact(topright_types_tests);
    const run_cli_tests = b.addRunArtifact(cli_tests);
    
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_main_tests.step);
    test_step.dependOn(&run_gid_tests.step);
    test_step.dependOn(&run_gstage_types_tests.step);
    test_step.dependOn(&run_gterminal_keys_tests.step);
    test_step.dependOn(&run_gterminal_screen_tests.step);
    test_step.dependOn(&run_gterminal_rawmode_tests.step);
    test_step.dependOn(&run_cli_tests.step);
    test_step.dependOn(&run_topright_chars_tests.step);
    test_step.dependOn(&run_topright_types_tests.step);
}
