# Contributing to Jenkins-to-EKS CI/CD Pipeline

Thank you for your interest in contributing! This document provides guidelines for contributing to this project.

## How to Contribute

### Reporting Bugs

If you find a bug, please create an issue with:
- Clear description of the problem
- Steps to reproduce
- Expected vs actual behavior
- Environment details (OS, versions, etc.)
- Logs or screenshots if applicable

### Suggesting Enhancements

For feature requests:
- Describe the feature and its benefits
- Provide use cases
- Suggest implementation approach if possible

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests if applicable
5. Update documentation
6. Commit with clear messages (`git commit -m 'Add amazing feature'`)
7. Push to your fork (`git push origin feature/amazing-feature`)
8. Open a Pull Request

### Code Style

- Follow PEP 8 for Python code
- Use meaningful variable and function names
- Add comments for complex logic
- Keep functions small and focused
- Write docstrings for functions and classes

### Testing

- Add unit tests for new features
- Ensure all tests pass before submitting PR
- Test in staging environment before production

### Documentation

- Update README.md if needed
- Add inline code comments
- Update relevant documentation files
- Include examples for new features

## Development Setup

```bash
# Clone repository
git clone https://github.com/SrinathMLOps/DevOpsCICD.git
cd DevOpsCICD

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r app/requirements.txt
pip install -r app/requirements-dev.txt  # If exists

# Run tests
cd app
pytest tests/
```

## Commit Message Guidelines

Format: `<type>(<scope>): <subject>`

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

Examples:
```
feat(pipeline): add security scanning stage
fix(helm): correct service port configuration
docs(readme): update setup instructions
```

## Code Review Process

1. Maintainers will review your PR
2. Address any feedback or requested changes
3. Once approved, PR will be merged
4. Your contribution will be acknowledged

## Community Guidelines

- Be respectful and inclusive
- Provide constructive feedback
- Help others learn and grow
- Follow the code of conduct

## Questions?

Feel free to open an issue for questions or reach out to maintainers.

Thank you for contributing!
