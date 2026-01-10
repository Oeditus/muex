-module(calculator).
-export([add/2, subtract/2, multiply/2, divide/2]).
-export([compare_equal/2, compare_greater/2]).

%% Arithmetic operations
add(A, B) -> A + B.

subtract(A, B) -> A - B.

multiply(A, B) -> A * B.

divide(A, B) -> A / B.

%% Comparison operations
compare_equal(A, B) -> A == B.

compare_greater(A, B) -> A > B.
