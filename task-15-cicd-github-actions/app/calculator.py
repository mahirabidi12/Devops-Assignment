"""A small calculator, used as the thing the pipeline builds and tests."""


class CalculatorError(ValueError):
    """Raised for inputs the calculator refuses to handle."""


def add(a: float, b: float) -> float:
    return a + b


def subtract(a: float, b: float) -> float:
    return a - b


def multiply(a: float, b: float) -> float:
    return a * b


def divide(a: float, b: float) -> float:
    if b == 0:
        raise CalculatorError("division by zero")
    return a / b


def power(base: float, exponent: float) -> float:
    return base ** exponent


def average(values: list[float]) -> float:
    if not values:
        raise CalculatorError("average of an empty sequence")
    return sum(values) / len(values)
