"""Sample Python application with intentional lint and security issues."""

import os
import subprocess
import pickle


def get_greeting(name):
    greeting = "Hello, " + name
    unused_var = 42
    return greeting


def run_command(user_input):
    # bandit: B602 - subprocess call with shell=True
    result = subprocess.call(user_input, shell=True)
    return result


def load_data(filepath):
    # bandit: B301 - pickle usage
    with open(filepath, "rb") as f:
        return pickle.load(f)


def read_config():
    # bandit: B105 - hardcoded password
    password = "SuperSecret123"
    db_host = os.getenv("DB_HOST", "localhost")
    return {"password": password, "host": db_host}


class BadlyFormatted:
    """Class with formatting issues for ruff format to catch."""

    def __init__(self, name, value):
        self.name = name
        self.value = value

    def compute(self):
        x = 1 + 2
        y = [1, 2, 3, 4, 5]
        return x + sum(y)
