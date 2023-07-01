from quadratic_equation import QuadraticEquationSolver
from pytest import approx, raises


def test_0_0_0():
    with raises(ZeroDivisionError) as e:
        QuadraticEquationSolver(0, 0, 0).solve()


def test_p1_0_0():
    assert QuadraticEquationSolver(1, 0, 0).solve() == [0]


def test_p1_p1_0():
    assert QuadraticEquationSolver(1, 1, 0).solve() == [0, -1]


def test_p1_n1_0():
    assert QuadraticEquationSolver(1, -1, 0).solve() == [1, 0]


def test_p1_p1_p1():
    assert QuadraticEquationSolver(1, 1, 1).solve() == []


