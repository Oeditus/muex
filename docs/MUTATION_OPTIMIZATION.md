# Mutation Optimization Heuristics

This document describes the sophisticated heuristics implemented in `Muex.MutantOptimizer` to reduce the number of mutants while maintaining mutation testing effectiveness.

## Overview

Mutation testing generates a large number of mutations, which can lead to long test execution times. The optimization heuristics intelligently filter and prioritize mutations to significantly reduce the number of mutants tested while preserving the ability to detect test suite weaknesses.

## Motivation

In real-world projects, mutation testing can generate hundreds or thousands of mutations:
- The Cart example (2 modules, ~440 LOC) generates **886-1541 mutations** depending on mutator configuration
- Testing all mutations can take minutes to hours
- Many mutations are redundant or low-value
- Some mutations are equivalent to the original code

Our goal: Reduce mutants by 50-70% while maintaining comparable mutation scores.

## Heuristic Strategies

### 1. Equivalent Mutant Detection

**Problem**: Some mutations are semantically equivalent to the original code and will never be killed by tests.

**Examples**:
- `x + 0` → `x - 0` (arithmetic identity)
- `x * 1` → `x / 1` (multiplicative identity)  
- `true and x` → `true or x` (short-circuit doesn't change behavior)
- Empty list mutations `[]` → `[]`

**Implementation**: Pattern matching on AST to detect known equivalent patterns.

**Impact**: Usually filters <5% of mutations (most are not equivalent).

### 2. Code Complexity Scoring

**Problem**: Simple code (getters, trivial guards) generates many mutations but is typically well-tested. Complex code with branching logic is more likely to contain subtle bugs.

**Approach**: Calculate a cyclomatic complexity approximation of the function each mutation is in:
```
complexity = count_decision_points(function) + 1

where function is the def, defp, defmacro or defmacrop clause around the mutation,
and decision_points include:
- if, case, cond, unless
- and, or, &&, ||
```

So `a > b` to `a < b` is kept inside a function that branches and dropped inside a one-line function that does not. Each clause of a multi-clause function is measured on its own. A mutation outside any function, such as in a module attribute, is measured by the node it replaces.

**Configuration**:
- `min_complexity: 2` (default) - Skip mutations in trivially simple code

**Impact**: Can filter 30-60% of mutations in validation-heavy code.

### 3. Impact Scoring

**Problem**: Not all mutations are equally valuable. Some reveal critical bugs; others test redundant paths.

**Scoring System**:

**Base Scores by Mutator Type**:
- Conditional mutations: 4 points (highest risk)
- Comparison mutations: 3 points (boundary conditions)
- Boolean mutations: 3 points
- Arithmetic mutations: 2 points
- FunctionCall mutations: 2 points
- Literal mutations: 1 point

**Complexity Bonuses**:
- Nested conditionals: +5 points
- Recursion or loops: +4 points
- Complex pattern matching: +3 points
- Multiple operations: +2 points

**Location Bonus**:
- Lines < 100 (typically public API): +1 point

**Example Impact Scores**:
- Simple literal mutation in validation: 1-2 points
- Arithmetic in complex calculation: 4-6 points
- Comparison in nested conditional: 8-11 points

### 4. Mutation Clustering

**Problem**: If a function has 10 arithmetic operations, testing all `+` → `-` mutations is redundant.

**Approach**:
1. Group mutations by function (50-line chunks)
2. Within each function, cluster by mutator type
3. Sample diverse representatives from each cluster
4. Keep top 33% (at least 2) based on impact score

**Configuration**:
- `cluster_similarity_threshold: 0.8` (default)

**Example**:
- Function with 12 arithmetic mutations → Keep 4 highest-impact
- Function with 3 comparison mutations → Keep all 3

**Impact**: 20-40% reduction in functions with many similar mutations.

### 5. Per-Function Limits

**Problem**: Some functions (especially validation or calculation-heavy code) can generate hundreds of mutations, dominating the test run.

**Approach**:
- Limit mutations per function to `max_mutations_per_function`
- Sort by impact score and keep highest-priority mutations

**Configuration**:
- `max_mutations_per_function: 20` (default)

**Rationale**: If a function has >20 mutations and tests are weak, you'll discover this from the highest-impact 20. Testing all 100 provides diminishing returns.

**Impact**: Significant reduction in complex functions; no impact on simple functions.

### 6. Boundary Mutation Prioritization

**Problem**: Boundary condition bugs (off-by-one errors) are common and critical.

**Approach**: Always preserve comparison mutations involving:
- `>=`, `<=` (boundary inclusive)
- `==`, `!=`, `===`, `!==` (equality)

These are kept regardless of complexity or clustering.

**Configuration**:
- `keep_boundary_mutations: true` (default)

**Rationale**: Boundary bugs are subtle and frequent. These mutations have high diagnostic value.

## Configuration

The optimizer can be configured with various options:

```elixir
MutantOptimizer.optimize(mutations,
  enabled: true,  # Enable optimization
  min_complexity: 2,  # Minimum complexity score
  max_mutations_per_function: 20,  # Limit per function
  cluster_similarity_threshold: 0.8,  # Clustering threshold
  keep_boundary_mutations: true  # Preserve boundary mutations
)
```

### Recommended Presets

**Conservative** (minimal reduction, ~30%):
```elixir
enabled: true,
min_complexity: 1,
max_mutations_per_function: 50,
keep_boundary_mutations: true
```

**Balanced** (moderate reduction, ~50-60%):
```elixir
enabled: true,
min_complexity: 2,
max_mutations_per_function: 20,
keep_boundary_mutations: true
```

**Aggressive** (maximum reduction, ~70-80%):
```elixir
enabled: true,
min_complexity: 3,
max_mutations_per_function: 10,
keep_boundary_mutations: true
```

## Results: Cart Example

### Baseline (No Optimization)
- Total mutations: 886
- Mutation score: 99.77%
- Estimated runtime: ~3 minutes

### With Balanced Optimization
- Total mutations: ~300-400 (50-55% reduction)
- Expected mutation score: 97-99% (±2%)
- Estimated runtime: ~1.5 minutes

### Benefits
1. **Faster feedback**: 50% reduction = 50% faster results
2. **Maintained quality**: Mutation score typically within 2% of baseline
3. **Focus on high-value mutations**: Average impact score increases from ~2 to ~5+
4. **Scalability**: Enables mutation testing on larger codebases

## When to Use Optimization

### Use Optimization When:
- Running mutation testing in CI/CD pipelines (time-constrained)
- Testing large modules or entire applications
- Initial mutation testing exploration
- Limited compute resources
- Rapid iteration during development

### Run Full Mutations When:
- Final validation before release
- Debugging specific test weaknesses
- Researching mutation testing effectiveness
- Unlimited compute/time available
- Very small codebases (<100 LOC)

## Validation

To validate that optimization maintains effectiveness:

1. Run baseline (no optimization):
   ```bash
   mix muex --files "lib/my_module.ex"
   ```

2. Run with optimization:
   ```bash
   mix muex --files "lib/my_module.ex" --optimize
   ```

3. Compare:
   - Mutation score should be within 2-5%
   - Runtime should be 40-70% faster
   - Survived mutations should be similar (not duplicates)

If mutation score drops significantly (>5%), the test suite may be weak in complex code areas. This is valuable information!

## Technical Implementation

The optimizer uses several Elixir AST analysis techniques:

1. **Pattern Matching**: Detect equivalent patterns
2. **AST Traversal**: Count decision points in each function for complexity (recorded on each mutation as `:function_complexity` by `Muex.Mutator.walk/3`)
3. **Metadata Analysis**: Use line numbers, mutator types for grouping
4. **Statistical Sampling**: Cluster and sample diverse representatives

Key implementation details:
- Handles both 3-tuple AST nodes and other node types
- Defensive coding for unknown AST patterns
- Preserves original mutation metadata (file, line, description)
- Maintains reproducibility (same input → same output)

## Future Enhancements

Potential improvements for future versions:

1. **Test Coverage Integration**: Prefer mutations in code covered by tests
2. **Historical Analysis**: Learn from past mutation results
3. **Domain-Specific Rules**: Custom heuristics per project type
4. **Machine Learning**: Train models to predict mutation value
5. **Incremental Testing**: Only test mutations in changed code
6. **Parallel Clustering**: Optimize clustering for very large codebases

## Conclusion

The mutation optimization heuristics significantly reduce testing time while maintaining the ability to detect test weaknesses. By focusing on high-impact, non-redundant mutations, developers get faster feedback without sacrificing quality.

The key insight: **Not all mutations are equally valuable**. Smart filtering preserves diagnostic power while eliminating redundancy.

---

For implementation details, see `lib/muex/mutant_optimizer.ex`.
