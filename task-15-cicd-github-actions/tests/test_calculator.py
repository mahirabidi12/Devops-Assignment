import pytest

from app.calculator import (
    CalculatorError,
    add,
    average,
    divide,
    multiply,
    power,
    subtract,
)


def test_add():
    assert add(2, 3) == 5
    assert add(-1, 1) == 0


def test_subtract():
    assert subtract(10, 4) == 6
    assert subtract(0, 5) == -5


def test_multiply():
    assert multiply(3, 4) == 12
    assert multiply(5, 0) == 0


def test_divide():
    assert divide(10, 2) == 5
    assert divide(7, 2) == 3.5


def test_divide_by_zero_raises():
    with pytest.raises(CalculatorError, match="division by zero"):
        divide(1, 0)


def test_power():
    assert power(2, 10) == 1024
    assert power(9, 0.5) == 3


def test_average():
    assert average([1, 2, 3, 4]) == 2.5


def test_average_of_empty_raises():
    with pytest.raises(CalculatorError, match="empty sequence"):
        average([])
