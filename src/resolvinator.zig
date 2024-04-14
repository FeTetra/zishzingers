const std = @import("std");

pub const MMTypes = @import("MMTypes.zig");
pub const Parser = @import("parser.zig");

pub const Libraries = std.StringHashMap(std.fs.Dir);

pub const ParsedScript = struct {
    pub const ImportedTypes = std.StringHashMap(void);
    /// Map of "imported name" to "original name + script"
    pub const ImportedFunctions = std.StringHashMap(struct {
        original_name: []const u8,
        script: []const u8,
    });

    /// The AST of the parsed script.
    ast: Parser.Tree,
    /// The name of the script.
    class_name: []const u8,
    /// Maps all the types which are imported.
    imported_types: ImportedTypes,
    /// Maps all the libraries imported.
    imported_libraries: Libraries,
    /// Maps all the imported functions which use the `from 'std:lams' import Translate;` syntax.
    imported_functions: ImportedFunctions,
    /// The identifier of the script.
    resource_identifier: MMTypes.ResourceIdentifier,
    /// Marks whether the script derives `Thing`, whether directly or indirectly.
    is_thing: bool,
};

pub const ParsedScriptTable = std.StringHashMap(*ParsedScript);

pub const Error = std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.ReadError || Parser.Error;

fn getScriptClassNode(tree: Parser.Tree) *Parser.Node.Class {
    for (tree.root_elements.items) |node| {
        switch (node) {
            .class => |class| return class,
            else => {},
        }
    }

    @panic("wathtsh");
}

fn getImportPathFromImportTarget(allocator: std.mem.Allocator, target: []const u8) ![]const u8 {
    var import_path = try allocator.alloc(u8, target.len + 3);

    @memcpy(import_path[0..target.len], target);
    @memcpy(import_path[target.len..], ".as");

    //Replace all the `:` with `/` in the import path
    std.mem.replaceScalar(u8, import_path, ':', '/');

    return import_path;
}

fn collectImportedTypes(class_name: []const u8, defined_libraries: Libraries, script_table: *ParsedScriptTable) Error!void {
    const script = script_table.get(class_name) orelse @panic("tsheointeonhsaoi");

    for (script.ast.root_elements.items) |item| {
        switch (item) {
            inline .import, .from_import => |import, import_type| {
                const import_path = try getImportPathFromImportTarget(script.ast.allocator, import.target);

                var found = false;

                var iter = script.imported_libraries.valueIterator();
                while (iter.next()) |library_dir| {
                    const import_file = library_dir.openFile(import_path, .{}) catch |err| {
                        if (err == std.fs.Dir.OpenError.FileNotFound)
                            continue;

                        return err;
                    };
                    defer import_file.close();

                    std.debug.print("reading {s}\n", .{import_path});

                    //Get all the lexemes into a single big array
                    const lexemes = blk: {
                        var lexemes = std.ArrayList([]const u8).init(script.ast.allocator);
                        defer lexemes.deinit();

                        var lexizer = Parser.Lexemeizer{ .source = try import_file.readToEndAlloc(script.ast.allocator, std.math.maxInt(usize)) };

                        while (try lexizer.next()) |lexeme| {
                            try lexemes.append(lexeme);
                        }

                        break :blk try lexemes.toOwnedSlice();
                    };

                    const ast = try Parser.parse(script.ast.allocator, lexemes);

                    const class = getScriptClassNode(ast);

                    if (script_table.get(class.name) == null)
                        try recursivelyResolveScript(ast, defined_libraries, script_table, null);

                    switch (comptime import_type) {
                        .import => {
                            try script.imported_types.putNoClobber(class.name, {});
                        },
                        .from_import => {
                            switch (import.wanted) {
                                .all => {
                                    for (class.functions) |function| {
                                        //TODO: this *needs* to be putNoClobber, I think these keys need to be the mangled names
                                        try script.imported_functions.put(function.name, .{
                                            .original_name = function.name,
                                            .script = class.name,
                                        });
                                    }
                                },
                                .multiple => |multiple_imports| {
                                    //TODO: check to make sure the original names actually exist in the script
                                    for (multiple_imports) |imported_function| {
                                        //TODO: this *needs* to be putNoClobber, I think these keys need to be the mangled names
                                        try script.imported_functions.put(imported_function.name, .{
                                            .original_name = imported_function.original_name,
                                            .script = class.name,
                                        });
                                    }
                                },
                                .single => |single_import| {
                                    //TODO: this *needs* to be putNoClobber, I think these keys need to be the mangled names
                                    try script.imported_functions.put(single_import.name, .{
                                        .original_name = single_import.original_name,
                                        .script = class.name,
                                    });
                                },
                            }
                        },
                        else => @compileError("THAE"),
                    }

                    found = true;
                }

                if (!found) std.debug.panic("could not find import {s}", .{import_path});
            },
            else => {},
        }
    }
}

fn collectImportedLibraries(script: *ParsedScript, defined_libraries: Libraries) Error!void {
    for (script.ast.root_elements.items) |item| {
        switch (item) {
            .using => |using| {
                if (using.type != .library)
                    @panic("unimplemented non-library using");

                try script.imported_libraries.putNoClobber(using.target, defined_libraries.get(using.target) orelse std.debug.panic("missing library {s}", .{using.target}));
            },
            else => {},
        }
    }
}

fn recursivelyResolveScript(tree: Parser.Tree, defined_libraries: Libraries, script_table: *ParsedScriptTable, script_identifier: ?MMTypes.ResourceIdentifier) Error!void {
    const class = getScriptClassNode(tree);

    const script = try tree.allocator.create(ParsedScript);
    script.* = ParsedScript{
        .ast = tree,
        .class_name = getScriptClassNode(tree).name,
        .imported_libraries = Libraries.init(tree.allocator),
        .imported_types = ParsedScript.ImportedTypes.init(tree.allocator),
        .imported_functions = ParsedScript.ImportedFunctions.init(tree.allocator),
        //Get the identifier for this script, whether it be passed in as a parameter or pulled from the class details
        .resource_identifier = script_identifier orelse switch ((class.identifier orelse @panic("you need to specify a identifier somewhere")).contents) {
            .guid_literal => |guid_literal| .{
                .guid = guid_literal,
            },
            else => @panic("TODO"),
        },
        .is_thing = undefined,
    };
    try script_table.putNoClobber(script.class_name, script);

    std.debug.print("resolving script {s}\n", .{script.class_name});

    //Collect all the libraries which are imported by the script
    try collectImportedLibraries(script, defined_libraries);

    //Collect all the script types which are imported
    try collectImportedTypes(script.class_name, defined_libraries, script_table);

    script.is_thing = isScriptThing(script, script_table);

    std.debug.print("script {s} is {} thing/notthing\n", .{ script.class_name, script.is_thing });
}

///Figures out if a script extends Thing, checks the full inheritance chain
fn isScriptThing(script: *const ParsedScript, script_table: *const ParsedScriptTable) bool {
    if (std.mem.eql(u8, script.class_name, "Thing"))
        return true;

    const class = getScriptClassNode(script.ast);

    if (class.base_class) |base_class| {
        return isScriptThing(script_table.get(base_class).?, script_table);
    } else {
        // This class is not Thing, and extends no other classes, therefor it cannot be a Thing
        return false;
    }
}

pub const AStringTable = std.StringArrayHashMap(void);

pub fn resolve(
    tree: Parser.Tree,
    defined_libraries: Libraries,
    a_string_table: *AStringTable,
    script_identifier: ?MMTypes.ResourceIdentifier,
) Error!void {
    var script_table = ParsedScriptTable.init(tree.allocator);
    defer script_table.deinit();

    try recursivelyResolveScript(tree, defined_libraries, &script_table, script_identifier);

    //Get the class of the script
    const class = getScriptClassNode(tree);

    const script = script_table.get(class.name) orelse unreachable;

    std.debug.print("type resolving {s}\n", .{script.class_name});

    for (class.fields) |field| {
        try resolveField(field, script, &script_table, a_string_table);
    }

    for (class.functions) |function| {
        try resolveFunctionHead(function, script, &script_table, a_string_table);
        try resolveFunctionBody(function, script, &script_table, a_string_table);
    }
}

fn resolveFunctionBody(
    function: *Parser.Node.Function,
    script: *ParsedScript,
    script_table: *ParsedScriptTable,
    a_string_table: *AStringTable,
) !void {
    if (function.body) |body| {
        var variable_stack = FunctionVariableStack.init(script.ast.allocator);
        defer variable_stack.deinit();

        var stack_info: FunctionVariableStackInfo = .{
            .current_level = 0,
            .stack = &variable_stack,
            .function = function,
        };

        if (body.type != .resolved)
            //TODO: once i parse the `=>` syntax for function bodies, this `null` for target type needs to be made correct!!!
            //      should i make function_body a special expression type? im not sure yet.
            //      maybe this could be as simple as "if block, target type == void, if not block, target type is the function return type" that should work
            try resolveExpression(
                body,
                null,
                script,
                script_table,
                a_string_table,
                &stack_info,
            );
    }

    std.debug.print("resolved function body {s}\n", .{function.name});
}

fn resolveFunctionHead(
    function: *Parser.Node.Function,
    script: *ParsedScript,
    script_table: *ParsedScriptTable,
    a_string_table: *AStringTable,
) !void {
    if (function.return_type != .resolved)
        function.return_type = .{
            .resolved = try resolveParsedType(
                function.return_type.parsed,
                script,
                script_table,
                a_string_table,
            ),
        };

    std.debug.print("resolved function return type as {}\n", .{function.return_type.resolved});

    for (function.parameters.parameters) |*parameter| {
        if (parameter.type != .resolved)
            parameter.type = .{
                .resolved = try resolveParsedType(
                    parameter.type.parsed,
                    script,
                    script_table,
                    a_string_table,
                ),
            };

        std.debug.print("resolved function parameter {s} as {}\n", .{ parameter.name, parameter.type.resolved });
    }

    std.debug.print("resolved function head {s}\n", .{function.name});
}

fn stringType(a_string_table: *AStringTable) !MMTypes.TypeReference {
    return .{
        .script = .{ .guid = 16491 },
        .type_name = @intCast((try a_string_table.getOrPut("String")).index),
        .machine_type = .object_ref,
        .fish_type = .void,
        .dimension_count = 0,
        .array_base_machine_type = .void,
    };
}

const FunctionVariableStack = std.StringArrayHashMap(struct {
    level: u8,
    type: Parser.Type,
});

const FunctionVariableStackInfo = struct {
    const StackLevel = u8;

    function: *Parser.Node.Function,
    current_level: StackLevel,
    stack: *FunctionVariableStack,
};

fn resolveExpression(
    expression: *Parser.Node.Expression,
    target_type: ?Parser.Type,
    script: *ParsedScript,
    script_table: *ParsedScriptTable,
    a_string_table: *AStringTable,
    function_variable_stack: ?*FunctionVariableStackInfo,
) !void {
    //At the end of this resolution, make sure the type got resolved to the target type
    defer if (target_type) |target_parsed_type|
        if (!target_parsed_type.resolved.eql(expression.type.resolved))
            std.debug.panic("wanted type {}, got type {}", .{ target_parsed_type.resolved, expression.type.resolved });

    //If this expression has already been resolved, do nothing
    if (expression.type == .resolved)
        return;

    std.debug.print("resolving {}\n", .{expression.contents});

    switch (expression.contents) {
        .s32_literal => {
            expression.type = .{
                .resolved = try resolveParsedType(
                    Parser.Type.ParsedType.S32,
                    script,
                    script_table,
                    a_string_table,
                ),
            };
        },
        .assignment => |assignment| {
            //Resolve the type of the destination
            try resolveExpression(
                assignment.destination,
                target_type,
                script,
                script_table,
                a_string_table,
                function_variable_stack,
            );

            //Resolve the type of the value, which should be the same type as the destination
            try resolveExpression(
                assignment.value,
                assignment.destination.type,
                script,
                script_table,
                a_string_table,
                function_variable_stack,
            );

            // The type of the expression is the type of the destination value
            // This is to allow constructs like `func(a = 2);`
            expression.type = assignment.destination.type;
        },
        .s64_literal => {
            expression.type = .{
                .resolved = try resolveParsedType(
                    Parser.Type.ParsedType.S64,
                    script,
                    script_table,
                    a_string_table,
                ),
            };
        },
        .variable_access => |variable_access| {
            const variable = function_variable_stack.?.stack.get(variable_access) orelse @panic("TODO: proper error here");

            std.debug.assert(variable.type == .resolved);

            expression.type = variable.type;
        },
        .bool_literal => {
            expression.type = .{
                .resolved = try resolveParsedType(
                    Parser.Type.ParsedType.Bool,
                    script,
                    script_table,
                    a_string_table,
                ),
            };
        },
        .wide_string_literal => {
            expression.type = .{ .resolved = try stringType(a_string_table) };
        },
        .function_call => |*function_call| {
            //First, figure out which function we want to call here...
            const function, const function_script = blk: {
                const local_class = getScriptClassNode(script.ast);

                // Iterate over all the functions defined in the local class, and prioritize them
                for (local_class.functions) |local_function| {
                    if (std.mem.eql(u8, local_function.name, function_call.function.name)) {
                        break :blk .{ local_function, script };
                    }
                }

                //TODO: handle calling overloads by checking param types... this code does not account for overloads *at all*. this is Not Good.
                //      why do people have to add overloads to things it *only* makes things harder. JUST NAME THINGS BETTER.
                //      im going to have to type resolve every imported function in every fucking imported script to be able to track overloads.
                //      like MAYBE i could only do the resolution when theres a conflict,
                //      but why the fuck should i have to? thats so much extra state tracking.
                //      just Dont Put Overloads In Your Language/VM you Bitch.
                if (script.imported_functions.get(function_call.function.name)) |imported_function| {
                    const original_script = script_table.get(imported_function.script).?;

                    const script_class = getScriptClassNode(original_script.ast);

                    for (script_class.functions) |imported_script_function| {
                        if (std.mem.eql(u8, function_call.function.name, imported_script_function.name))
                            break :blk .{ imported_script_function, original_script };
                    }

                    unreachable;
                }

                std.debug.panic("unable to find function {s}", .{function_call.function.name});
            };
            std.debug.print("found func {s} for call {s}\n", .{ function.name, function_call.function.name });
            try resolveFunctionHead(function, function_script, script_table, a_string_table);

            function_call.function = .{ .function = function };

            // Resolve all the call parameter expressions to the types of the function parameters
            for (function.parameters.parameters, function_call.parameters) |parameter, call_parameter| {
                try resolveExpression(
                    call_parameter,
                    parameter.type,
                    script,
                    script_table,
                    a_string_table,
                    function_variable_stack,
                );
            }

            expression.type = function.return_type;
        },
        .block => |block| {
            expression.type = .{
                .resolved = try resolveParsedType(
                    Parser.Type.ParsedType.Void,
                    script,
                    script_table,
                    a_string_table,
                ),
            };

            function_variable_stack.?.current_level += 1;
            defer {
                var iter = function_variable_stack.?.stack.iterator();
                while (iter.next()) |variable| {
                    if (variable.value_ptr.level == function_variable_stack.?.current_level) {
                        std.debug.assert(function_variable_stack.?.stack.orderedRemove(variable.key_ptr.*));

                        iter.index -= 1;
                        iter.len -= 1;
                    }
                }
                function_variable_stack.?.current_level -= 1;
            }

            for (function_variable_stack.?.function.parameters.parameters) |parameter| {
                try function_variable_stack.?.stack.put(parameter.name, .{
                    .level = function_variable_stack.?.current_level,
                    .type = parameter.type,
                });
            }

            //Resolve the contents
            for (block) |node| {
                switch (node) {
                    .variable_declaration => |variable_declaration| {
                        if (variable_declaration.type == .unknown) {
                            //If the type of the variable declaration is unspecified, we need to resolve the value expression first
                            if (variable_declaration.value) |value| {
                                try resolveExpression(
                                    value,
                                    null,
                                    script,
                                    script_table,
                                    a_string_table,
                                    function_variable_stack,
                                );

                                //Then we can use the type of the value expression for the type of the variable declaration
                                variable_declaration.type = variable_declaration.value.?.type;
                            }
                            //This should be an impossible scenario, the parser gets mad about this
                            else unreachable;
                        } else {
                            //Resolve the variable declaration type
                            variable_declaration.type = .{
                                .resolved = try resolveParsedType(
                                    variable_declaration.type.parsed,
                                    script,
                                    script_table,
                                    a_string_table,
                                ),
                            };

                            //If the variable declaration has a value set, resolve the value expression to the type of the variable
                            if (variable_declaration.value) |value| {
                                try resolveExpression(
                                    value,
                                    variable_declaration.type,
                                    script,
                                    script_table,
                                    a_string_table,
                                    function_variable_stack,
                                );
                            }
                        }

                        try function_variable_stack.?.stack.put(variable_declaration.name, .{
                            .level = function_variable_stack.?.current_level,
                            .type = variable_declaration.type,
                        });
                    },
                    .expression => |node_expression| {
                        try resolveExpression(
                            node_expression,
                            target_type,
                            script,
                            script_table,
                            a_string_table,
                            function_variable_stack,
                        );
                    },
                    else => |node_type| std.debug.panic("TODO: resolution of expression type {s}", .{@tagName(node_type)}),
                }
            }
        },
        else => |contents| std.debug.panic("TODO: resolution of expression type {s}", .{@tagName(contents)}),
    }
}

fn resolveParsedType(
    parsed_type: Parser.Type.ParsedType,
    script: *ParsedScript,
    script_table: *ParsedScriptTable,
    a_string_table: *AStringTable,
) !MMTypes.TypeReference {
    if (std.meta.stringToEnum(MMTypes.FishType, parsed_type.name)) |fish_type| {
        return if (parsed_type.dimension_count > 0)
            MMTypes.TypeReference{
                .array_base_machine_type = fish_type.toMachineType(),
                .dimension_count = parsed_type.dimension_count,
                .fish_type = .void,
                .machine_type = .object_ref,
                //null
                .type_name = 0xFFFFFFFF,
                .script = null,
            }
        else
            MMTypes.TypeReference{
                .array_base_machine_type = .void,
                .dimension_count = 0,
                .fish_type = fish_type,
                .machine_type = fish_type.toMachineType(),
                //null
                .type_name = 0xFFFFFFFF,
                .script = null,
            };
    } else {
        var iter = script.imported_types.keyIterator();
        while (iter.next()) |imported_type| {
            if (std.mem.eql(u8, parsed_type.name, imported_type.*)) {
                const referenced_script = script_table.get(imported_type.*).?;

                //Get the idx of the name of this script, or put into the string table
                const name_idx = try a_string_table.getOrPut(imported_type.*);

                return if (parsed_type.dimension_count > 0)
                    MMTypes.TypeReference{
                        .array_base_machine_type = if (referenced_script.is_thing) .safe_ptr else .object_ref,
                        .dimension_count = parsed_type.dimension_count,
                        .fish_type = .void,
                        .machine_type = .object_ref,
                        .type_name = @intCast(name_idx.index),
                        .script = referenced_script.resource_identifier,
                    }
                else
                    MMTypes.TypeReference{
                        .array_base_machine_type = .void,
                        .dimension_count = 0,
                        .fish_type = .void,
                        .machine_type = if (referenced_script.is_thing) .safe_ptr else .object_ref,
                        .type_name = @intCast(name_idx.index),
                        .script = referenced_script.resource_identifier,
                    };
            }
        }

        @panic("no script found.");
    }
}

fn resolveField(
    field: *Parser.Node.Field,
    script: *ParsedScript,
    script_table: *ParsedScriptTable,
    a_string_table: *AStringTable,
) !void {
    std.debug.print("type resolving field {s}\n", .{field.name});

    switch (field.type) {
        .parsed => |parsed_type| {
            field.type = .{
                .resolved = try resolveParsedType(
                    parsed_type,
                    script,
                    script_table,
                    a_string_table,
                ),
            };
        },
        .unknown => {
            if (field.default_value) |default_value| {
                //Resolve the type of the default value, with no specific target type in mind
                try resolveExpression(
                    default_value,
                    null,
                    script,
                    script_table,
                    a_string_table,
                    null,
                );

                //Set the type of the field to the resolved default value type
                field.type = default_value.type;
            } else unreachable;
        },
        else => unreachable,
    }

    std.debug.print("resolved as {}\n", .{field.type});

    std.debug.assert(field.type == .resolved);
}
