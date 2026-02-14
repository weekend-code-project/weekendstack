# WeekendStack Test Suite

Comprehensive testing framework for WeekendStack setup scripts and configuration.

## Quick Start

```bash
# Run all tests
./tools/test/run-tests.sh

# Run specific test category
./tools/test/run-tests.sh unit
./tools/test/run-tests.sh integration
./tools/test/run-tests.sh smoke
```

## Test Categories

### Unit Tests (`tools/test/unit/`)
Test individual functions and components in isolation.

- **test_env_generator.sh**: Tests for environment file generation
  - update_env_var function with special characters
  - Template generation with random secrets
  - Handling of variables with numbers (N8N_*)
  
- **test_validation.sh**: Tests for configuration validation
  - Weak password detection
  - Required field validation
  - Inline comment handling
  - IP address format validation
  
- **test_profile_selector.sh**: Tests for profile selection
  - Profile description completeness
  - Existing profile detection
  - .env parsing

### Integration Tests (`tools/test/integration/`)
Test interactions between components.

- **test_docker_compose.sh**: Docker Compose configuration validation
  - YAML syntax validation
  - Profile file existence
  - Compose file includes

### Smoke Tests (`tools/test/smoke/`)
Quick tests to verify basic functionality.

- **test_services_start.sh**: Basic environment checks
  - Docker daemon status
  - Docker Compose availability
  - Network creation capability
  - Image pull capability

## Writing Tests

### Test Structure

```bash
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "Your Test Suite Name"

test_case "Description of what you're testing"
# Your test code here
if [[ condition ]]; then
    test_pass
else
    test_fail "Error message"
fi

test_case "Another test"
# More test code

test_suite_end
```

### Helper Functions

- `test_suite_start "Name"` - Start a test suite
- `test_suite_end` - End suite and show results
- `test_case "Description"` - Start a test case
- `test_pass` - Mark test as passed
- `test_fail "Message"` - Mark test as failed with message
- `test_skip "Reason"` - Skip a test
- `create_temp_env` - Create temporary test environment
- `backup_file "path"` - Backup a file before testing
- `restore_file "path"` - Restore backed up file
- `update_env_var "VAR" "value" "file"` - Update .env variable safely

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Test Suite
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run tests
        run: ./tools/test/run-tests.sh
```

### Pre-commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit
./tools/test/run-tests.sh unit
```

## Adding New Tests

1. **Choose the category**: unit, integration, or smoke
2. **Create test file**: `tools/test/<category>/test_yourfeature.sh`
3. **Make executable**: `chmod +x tools/test/<category>/test_yourfeature.sh`
4. **Use test helpers**: Source `test_helpers.sh`
5. **Run tests**: `./tools/test/run-tests.sh`

## Regression Testing

When fixing bugs:

1. Write a test that reproduces the bug
2. Verify the test fails
3. Fix the bug
4. Verify the test passes
5. Commit both fix and test

## Test Coverage

Current test coverage focuses on:
- ✅ Environment file generation with special characters
- ✅ Random secret generation
- ✅ Configuration validation
- ✅ Docker Compose syntax
- ✅ Basic Docker functionality

Future coverage areas:
- [ ] Full setup.sh integration test
- [ ] Service startup verification
- [ ] Cloudflare tunnel configuration
- [ ] Profile layering logic
- [ ] Directory creation
- [ ] Docker network setup

## Troubleshooting

### Tests fail with "Permission denied"
```bash
chmod +x tools/test/run-tests.sh
chmod +x tools/test/unit/*.sh
chmod +x tools/test/integration/*.sh
chmod +x tools/test/smoke/*.sh
```

### Tests modify .env file
Tests automatically backup and restore `.env` files. If interrupted, check for `.env.test-backup`.

### Docker tests fail
Ensure Docker daemon is running:
```bash
sudo systemctl start docker
docker info
```

## Performance

Typical test run times:
- Unit tests: ~5-10 seconds
- Integration tests: ~5-10 seconds
- Smoke tests: ~10-15 seconds
- **Total (all)**: ~20-35 seconds

## Contributing

When contributing new features:

1. Write tests first (TDD approach)
2. Ensure all existing tests pass
3. Add tests for new functionality
4. Update this README if adding new test categories

## License

Same as WeekendStack main project.
