from quadratic_equation import QuadraticEquationSolver
from pytest import approx, raises


def test_0_0_0():
    with raises(ZeroDivisionError):
        QuadraticEquationSolver(0, 0, 0).solve()


def test_p1_0_0():
    assert QuadraticEquationSolver(1, 0, 0).solve() == [0]


def test_p1_p1_0():
    assert QuadraticEquationSolver(1, 1, 0).solve() == [0, -1]


def test_p1_n1_0():
    assert QuadraticEquationSolver(1, -1, 0).solve() == [1, 0]


def test_p1_p1_p1():
    assert QuadraticEquationSolver(1, 1, 1).solve() == []


def test_p1_p1_n1():
    assert QuadraticEquationSolver(1, 1, -1).solve() == [
        approx(-0.5 + 0.5 * (5 ** 0.5)),
        approx(-0.5 - 0.5 * (5 ** 0.5)),
    ]


def test_p1_n1_p1():
    assert QuadraticEquationSolver(1, -1, 1).solve() == []


def test_p1_n1_n1():
    assert QuadraticEquationSolver(1, -1, -1).solve() == [
        approx(0.5 - 0.5 * (5 ** 0.5)),
        approx(0.5 + 0.5 * (5 ** 0.5)),
    ]


def test_p2_p2_p1():
    assert QuadraticEquationSolver(2, 2, 1).solve() == [-0.5]


def test_n2_n2_p1():
    assert QuadraticEquationSolver(-2, -2, 1).solve() == [-0.5]


def test_p2_n2_p1():
    assert QuadraticEquationSolver(2, -2, 1).solve() == []


def test_p2_p2_n1():
    assert QuadraticEquationSolver(2, 2, -1).solve() == [approx(-1), approx(0.5)]


def test_n2_n2_n1():
    assert QuadraticEquationSolver(-2, -2, -1).solve() == [approx(-1), approx(0.5)]


def custom_test():
    # Add your custom test case here
    assert QuadraticEquationSolver(2, 5, -3).solve() == [approx(-3), approx(0.5)]


# Run all the tests
def run_tests():
    test_0_0_0()
    test_p1_0_0()
    test_p1_p1_0()
    test_p1_n1_0()
    test_p1_p1_p1()
    test_p1_p1_n1()
    test_p1_n1_p1()
    test_p1_n1_n1()
    test_p2_p2_p1()
    test_n2_n2_p1()
    test_p2_n2_p1()
    test_p2_p2_n1()
    test_n2_n2_n1()
    custom_test()


run_tests()
