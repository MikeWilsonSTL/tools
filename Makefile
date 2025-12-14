# SPDX-FileCopyrightText: 2025 Mike Wilson
# SPDX-License-Identifier: GPL-3.0-or-later

.PHONY: lint shellcheck reuse test

# Run ShellCheck on all scripts
shellcheck:
	@echo "Running ShellCheck..."
	@shellcheck -x ./scripts/*.sh

# Run REUSE lint
reuse:
	@echo "Running REUSE lint..."
	@reuse lint

# Run all linting
lint: shellcheck reuse
	@echo "All checks passed!"

# Placeholder for tests
test:
	@echo "No tests yet"
	# if running -e making sure that all functions use return instead of exit for WSL stability

