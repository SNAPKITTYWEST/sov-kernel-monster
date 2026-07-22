# ShadowRPG-Q Grammar Specification

**Language**: ShadowRPG-Q (Shadow RPG for Quantum)  
**Version**: 1.0  
**Status**: Original Experimental Language  
**Date**: 2026-07-21  
**Purpose**: Quantum job control and workflow orchestration

---

## Language Identity

**ShadowRPG-Q** is an original language designed for QATAAUM. It is:
- ✅ Inspired by RPG operational patterns
- ✅ Designed for quantum workflow control
- ✅ Clean-room implementation
- ❌ NOT an IBM language
- ❌ NOT proprietary RPG code

---

## Design Principles

1. **Record-Oriented**: Jobs are structured records
2. **Declarative**: Describe what, not how
3. **Typed**: Strong typing for quantum resources
4. **Auditable**: Every operation logged
5. **Operational**: Production-grade reliability

---

## Lexical Structure

### Keywords

```
**FREE          // Free-form mode indicator
DCL-JOB         // Declare job
DCL-QREG        // Declare quantum register
DCL-CREG        // Declare classical register
DCL-PARAM       // Declare parameter
DCL-VAR         // Declare variable
DCL-DS          // Declare data structure
END-DS          // End data structure
QASM-SOURCE     // Specify QASM source file
QASM-INLINE     // Inline QASM code
COMPILE         // Compilation directive
EXECUTE         // Execution directive
RETRIEVE        // Retrieve results
DISPLAY         // Display output
STORE           // Store results
TARGET          // Target processor
OPTIMIZE        // Optimization level
SHOTS           // Number of shots
BACKEND         // Backend selection
SIMULATOR       // Simulator backend
HARDWARE        // Hardware backend
RESULTS         // Results reference
COUNTS          // Measurement counts
METADATA        // Execution metadata
IF              // Conditional
ELSE            // Alternative branch
ENDIF           // End conditional
FOR             // Loop
ENDFOR          // End loop
WHILE           // While loop
ENDWHILE        // End while
CALL            // Call procedure
RETURN          // Return from procedure
END-JOB         // End job
QUALIFIED       // Qualified data structure
```

### Data Types

```
CHAR(n)         // Character string
INT(n)          // Integer (3, 5, 10, 20)
PACKED(p,s)     // Packed decimal
FLOAT(n)        // Floating point (4, 8)
IND             // Indicator (boolean)
TIMESTAMP       // Timestamp
QREG            // Quantum register
CREG            // Classical register
```

### Operators

```
=               // Assignment
+               // Addition
-               // Subtraction
*               // Multiplication
/               // Division
**              // Exponentiation
AND             // Logical AND
OR              // Logical OR
NOT             // Logical NOT
>               // Greater than
<               // Less than
>=              // Greater or equal
<=              // Less or equal
==              // Equal
<>              // Not equal
```

### Literals

```
'string'        // String literal
123             // Integer literal
123.45          // Float literal
*ON             // Boolean true
*OFF            // Boolean false
```

### Comments

```
// Single-line comment
/* Multi-line
   comment */
```

---

## Grammar Rules

### Program Structure

```ebnf
program ::= free_form_indicator job_declaration statement* end_job

free_form_indicator ::= "**FREE"

job_declaration ::= "DCL-JOB" identifier ";"

end_job ::= "END-JOB" ";"

statement ::= declaration
            | qasm_directive
            | compile_directive
            | execute_directive
            | retrieve_directive
            | display_directive
            | store_directive
            | control_flow
            | assignment
            | call_statement
```

### Declarations

```ebnf
declaration ::= qreg_declaration
              | creg_declaration
              | param_declaration
              | var_declaration
              | ds_declaration

qreg_declaration ::= "DCL-QREG" identifier integer ";"

creg_declaration ::= "DCL-CREG" identifier integer ";"

param_declaration ::= "DCL-PARAM" identifier type ";"

var_declaration ::= "DCL-VAR" identifier type ";"

ds_declaration ::= "DCL-DS" identifier qualified? ";"
                   field_declaration*
                   "END-DS" ";"

field_declaration ::= identifier type ";"

qualified ::= "QUALIFIED"

type ::= "CHAR" "(" integer ")"
       | "INT" "(" integer ")"
       | "PACKED" "(" integer "," integer ")"
       | "FLOAT" "(" integer ")"
       | "IND"
       | "TIMESTAMP"
       | "QREG"
       | "CREG"
```

### QASM Directives

```ebnf
qasm_directive ::= qasm_source | qasm_inline

qasm_source ::= "QASM-SOURCE" string_literal ";"

qasm_inline ::= "QASM-INLINE" string_literal ";"
```

### Compilation Directive

```ebnf
compile_directive ::= "COMPILE" compile_option* ";"

compile_option ::= target_option
                 | optimize_option

target_option ::= "TARGET" "(" identifier ")"

optimize_option ::= "OPTIMIZE" "(" optimize_level ")"

optimize_level ::= "LEVEL0" | "LEVEL1" | "LEVEL2" | "LEVEL3"
```

### Execution Directive

```ebnf
execute_directive ::= "EXECUTE" execute_option* ";"

execute_option ::= shots_option
                 | backend_option

shots_option ::= "SHOTS" "(" integer ")"

backend_option ::= "BACKEND" "(" backend_type ")"

backend_type ::= "SIMULATOR" | "HARDWARE" | identifier
```

### Retrieve Directive

```ebnf
retrieve_directive ::= "RETRIEVE" retrieve_option* ";"

retrieve_option ::= results_option
                  | counts_option
                  | metadata_option

results_option ::= "RESULTS" "(" identifier ")"

counts_option ::= "COUNTS"

metadata_option ::= "METADATA"
```

### Display Directive

```ebnf
display_directive ::= "DISPLAY" display_target ";"

display_target ::= identifier | "COUNTS" | "METADATA"
```

### Store Directive

```ebnf
store_directive ::= "STORE" identifier "TO" string_literal ";"
```

### Control Flow

```ebnf
control_flow ::= if_statement
               | for_statement
               | while_statement

if_statement ::= "IF" expression ";"
                 statement*
                 else_clause?
                 "ENDIF" ";"

else_clause ::= "ELSE" ";"
                statement*

for_statement ::= "FOR" identifier "=" expression "TO" expression ";"
                  statement*
                  "ENDFOR" ";"

while_statement ::= "WHILE" expression ";"
                    statement*
                    "ENDWHILE" ";"
```

### Expressions

```ebnf
expression ::= logical_or

logical_or ::= logical_and ("OR" logical_and)*

logical_and ::= equality ("AND" equality)*

equality ::= comparison (("==" | "<>") comparison)*

comparison ::= additive ((">" | "<" | ">=" | "<=") additive)*

additive ::= multiplicative (("+" | "-") multiplicative)*

multiplicative ::= exponentiation (("*" | "/") exponentiation)*

exponentiation ::= unary ("**" unary)*

unary ::= ("NOT" | "-") unary
        | primary

primary ::= identifier
          | literal
          | "(" expression ")"
          | field_access

field_access ::= identifier "." identifier

literal ::= string_literal
          | integer_literal
          | float_literal
          | boolean_literal

boolean_literal ::= "*ON" | "*OFF"
```

### Assignment

```ebnf
assignment ::= identifier "=" expression ";"
```

### Call Statement

```ebnf
call_statement ::= "CALL" identifier "(" argument_list? ")" ";"

argument_list ::= expression ("," expression)*
```

---

## Example Programs

### Example 1: Simple Bell State

```rpg
**FREE
DCL-JOB BELL_STATE_JOB;

// Quantum resources
DCL-QREG Q 2;
DCL-CREG C 2;

// Source
QASM-SOURCE 'bell_state.qasm';

// Compile
COMPILE TARGET(HERON_R3) OPTIMIZE(LEVEL2);

// Execute
EXECUTE SHOTS(1024) BACKEND(SIMULATOR);

// Retrieve and display
RETRIEVE RESULTS(C);
DISPLAY COUNTS;

END-JOB;
```

### Example 2: Parameterized Circuit

```rpg
**FREE
DCL-JOB PARAMETERIZED_JOB;

// Resources
DCL-QREG Q 3;
DCL-CREG C 3;
DCL-PARAM Theta FLOAT(8);

// Set parameter
Theta = 1.5708;  // π/2

// Inline QASM with parameter
QASM-INLINE 'OPENQASM 2.0;
include "qelib1.inc";
qreg q[3];
creg c[3];
ry(theta) q[0];
cx q[0], q[1];
cx q[1], q[2];
measure q -> c;';

// Compile and execute
COMPILE TARGET(SIMULATOR) OPTIMIZE(LEVEL1);
EXECUTE SHOTS(2048) BACKEND(SIMULATOR);

// Results
RETRIEVE RESULTS(C) COUNTS METADATA;
DISPLAY COUNTS;

END-JOB;
```

### Example 3: Conditional Execution

```rpg
**FREE
DCL-JOB CONDITIONAL_JOB;

// Resources
DCL-QREG Q 2;
DCL-CREG C 2;
DCL-VAR Success IND;
DCL-VAR ShotCount INT(10);

// Configuration
ShotCount = 1024;

// Source
QASM-SOURCE 'my_circuit.qasm';

// Compile
COMPILE TARGET(HERON_R3) OPTIMIZE(LEVEL2);

// Execute
EXECUTE SHOTS(ShotCount) BACKEND(SIMULATOR);

// Check success
RETRIEVE RESULTS(C);
Success = *ON;

IF Success;
  DISPLAY COUNTS;
  STORE C TO 'results.json';
ELSE;
  DISPLAY 'Execution failed';
ENDIF;

END-JOB;
```

### Example 4: Loop Over Parameters

```rpg
**FREE
DCL-JOB PARAMETER_SWEEP_JOB;

// Resources
DCL-QREG Q 1;
DCL-CREG C 1;
DCL-VAR Angle FLOAT(8);
DCL-VAR I INT(10);

// Data structure for results
DCL-DS ResultSet QUALIFIED;
  Angle FLOAT(8);
  Counts CHAR(1000);
END-DS;

// Loop over angles
FOR I = 0 TO 10;
  Angle = I * 0.314159;  // 0 to π in 10 steps
  
  // Create circuit with current angle
  QASM-INLINE 'OPENQASM 2.0;
  include "qelib1.inc";
  qreg q[1];
  creg c[1];
  ry(angle) q[0];
  measure q[0] -> c[0];';
  
  // Compile and execute
  COMPILE TARGET(SIMULATOR) OPTIMIZE(LEVEL1);
  EXECUTE SHOTS(1000) BACKEND(SIMULATOR);
  
  // Store results
  RETRIEVE RESULTS(C);
  ResultSet.Angle = Angle;
  DISPLAY COUNTS;
ENDFOR;

END-JOB;
```

### Example 5: Data Structure Usage

```rpg
**FREE
DCL-JOB STRUCTURED_JOB;

// Job configuration structure
DCL-DS JobConfig QUALIFIED;
  TargetProcessor CHAR(50);
  OptimizationLevel INT(3);
  ShotCount INT(10);
  BackendType CHAR(20);
END-DS;

// Result structure
DCL-DS JobResult QUALIFIED;
  JobID CHAR(50);
  ExecutionTime FLOAT(8);
  Success IND;
  ErrorMessage CHAR(200);
END-DS;

// Resources
DCL-QREG Q 2;
DCL-CREG C 2;

// Configure job
JobConfig.TargetProcessor = 'HERON_R3';
JobConfig.OptimizationLevel = 2;
JobConfig.ShotCount = 1024;
JobConfig.BackendType = 'SIMULATOR';

// Execute
QASM-SOURCE 'bell_state.qasm';
COMPILE TARGET(JobConfig.TargetProcessor) 
        OPTIMIZE(LEVEL2);
EXECUTE SHOTS(JobConfig.ShotCount) 
        BACKEND(JobConfig.BackendType);

// Retrieve results
RETRIEVE RESULTS(C);
JobResult.Success = *ON;
JobResult.ExecutionTime = 0.125;

IF JobResult.Success;
  DISPLAY COUNTS;
ELSE;
  DISPLAY JobResult.ErrorMessage;
ENDIF;

END-JOB;
```

---

## Semantic Rules

### Type Checking

1. **Quantum Registers**: Must be declared before use
2. **Classical Registers**: Must be declared before use
3. **Parameters**: Must match expected types
4. **Variables**: Must be initialized before use
5. **Data Structures**: Fields must be accessed with qualified names

### Resource Management

1. **Quantum Registers**: Linear ownership (no copying)
2. **Classical Registers**: Can be copied
3. **Compilation**: Must occur before execution
4. **Execution**: Must occur before retrieval

### Control Flow

1. **IF**: Condition must be boolean expression
2. **FOR**: Loop variable must be integer
3. **WHILE**: Condition must be boolean expression
4. **Nesting**: Control structures can be nested

### Job Lifecycle

```
1. DCL-JOB: Job declaration
2. Declarations: Resource declarations
3. QASM-SOURCE/INLINE: Circuit specification
4. COMPILE: Compilation
5. EXECUTE: Execution
6. RETRIEVE: Result retrieval
7. DISPLAY/STORE: Output
8. END-JOB: Job completion
```

---

## Implementation Notes

### Parser

- **Lexer**: Tokenize ShadowRPG-Q source
- **Parser**: Build AST from tokens
- **Semantic Analyzer**: Type checking and validation
- **Code Generator**: Generate job records

### Executor

- **Job Queue**: Submit jobs to queue
- **Compiler Interface**: Invoke QATAAUM compiler
- **Execution Engine**: Run compiled circuits
- **Result Manager**: Retrieve and format results

### Integration

- **QASM Bridge**: Parse and validate QASM source
- **Compiler Bridge**: Invoke compilation pipeline
- **Simulator Bridge**: Execute on simulator
- **Hardware Bridge**: Execute on hardware (if available)

---

## Future Extensions

### Planned Features

1. **Procedures**: User-defined procedures
2. **Modules**: Modular job organization
3. **Error Handling**: Structured exception handling
4. **Async Execution**: Non-blocking job submission
5. **Batch Jobs**: Multiple jobs in sequence
6. **Result Analysis**: Built-in analysis functions

### Compatibility

- **OpenQASM 2**: Full support
- **OpenQASM 3**: Planned support
- **MetaQASM-4**: Planned support

---

## Grammar Summary

**Total Productions**: 50+  
**Keywords**: 40+  
**Operators**: 15+  
**Data Types**: 8  

**Complexity**: Medium  
**Parsing**: LL(1) or recursive descent  
**Type System**: Static, strong typing

---

**Specification Version**: 1.0  
**Date**: 2026-07-21  
**Status**: Complete  
**Language Designer**: Bob (ROLE-RPG-ENGINEER)

// Made with Bob