"""Succeed when the greeter shows the requested account label."""

import sys

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi


def shows_user(node, name):
    if node is None:
        return False
    if node.get_role() == Atspi.Role.LABEL and (node.get_name() or "").casefold() == name:
        return node.get_state_set().contains(Atspi.StateType.SHOWING)
    return any(shows_user(node.get_child_at_index(i), name) for i in range(node.get_child_count()))


sys.exit(0 if shows_user(Atspi.get_desktop(0), sys.argv[1].casefold()) else 1)
