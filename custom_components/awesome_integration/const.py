"""Constants for awesome_integration."""

from logging import Logger, getLogger

LOGGER: Logger = getLogger(__package__)

DOMAIN = "awesome_integration"
ATTRIBUTION = "Data provided by the vacuum outcome timeline"

# Custom project constants (would be clobbered by an upstream -X theirs sync)
SCAN_INTERVAL_SECONDS = 30
OUTCOME_CLASSES = ["completed", "aborted", "error", "stuck"]

