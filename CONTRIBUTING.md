# Contributing to Diaspora Nearby

Thank you for your interest in contributing to Diaspora Nearby! We welcome all contributions that help improve this project.

## Code of Conduct

Please be respectful and professional in all interactions within this project.

## Project Source of Truth: Conductor

> **⚠️ IMPORTANT**: Before contributing, review the [`conductor/`](conductor/) directory.

The conductor system is our project's **authoritative source of truth**:
- **[CONDUCTOR.md](conductor/CONDUCTOR.md)** - Approved changes & core instructions
- **[product.md](conductor/product.md)** - Product vision & features
- **[tech-stack.md](conductor/tech-stack.md)** - Technology inventory
- **[tracks.md](conductor/tracks.md)** - Development progress
- **[workflow.md](conductor/workflow.md)** - Development guidelines

**Key Principle**: Always refer to the codebase and conductor files for current logic. Other markdown documentation may be outdated.


## How to Contribute

### Reporting Bugs
If you find a bug, please create an issue on GitHub with:
- A clear, descriptive title.
- Steps to reproduce the issue.
- Expected vs. actual behavior.
- Screenshots if applicable.

### Suggesting Enhancements
We love new ideas! Please open an issue to discuss any major enhancements before starting work.

### Git Flow Workflow

We follow a **Git Flow** strategy with these branches:

#### Core Branches
- **`main`** - Production-ready code (protected, PR only)
- **`develop`** - Integration branch (default working branch)

#### Working Branches
- **`feature/*`** - New features (branch from `develop`)
- **`bugfix/*`** - Bug fixes (branch from `develop`)
- **`hotfix/*`** - Critical fixes (branch from `main`)

#### Workflow Steps

```bash
# 1. Start new work
git checkout develop
git pull origin develop
git checkout -b feature/your-feature-name

# 2. Commit your changes
git add .
git commit -m "feat: describe your change"

# 3. Keep updated with develop
git fetch origin
git rebase origin/develop

# 4. Push and create PR
git push origin feature/your-feature-name
# Create PR targeting 'develop'
```

#### Commit Convention
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation
- `refactor:` - Code restructuring
- `test:` - Testing
- `chore:` - Build/tooling

### Before Submitting PR
1. Run `flutter analyze` (must pass)
2. Run `flutter test` (all tests must pass)
3. Use `dart format .` for code formatting
4. Write tests for new features (see [Testing Guide](test/README.md))

### Testing Requirements

All new code should include appropriate tests:
- **Services & Repositories** - Unit tests required
- **Widgets** - Widget tests for complex components
- **New Features** - Integration tests for critical flows

See our comprehensive [Testing Guide](test/README.md) for:
- How to write unit, widget, and integration tests
- Using test utilities and mocks
- Best practices and examples

## Development Setup

See the [README.md](README.md) for installation and setup instructions.

### Coding Standards
- Use `dart format` for consistent code formatting.
- Follow the official [Dart style guide](https://dart.dev/guides/language/effective-dart/style).
- Ensure all new widgets have clear documentation and follow the existing theme.
