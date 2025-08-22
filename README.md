# 🪽 uvget 🪽

Install executable Python packages from PyPI via UV without prerequisites. This allows reusing the script as a drop-in replacement and distribution mechanism for Python-based CLI tools, TUIs, and others. Instead of dealing with the complexity of packaging your Python apps into self-contained binaries, let UV handle the hard work.

## Install

**Unix/Linux/macOS:**
```bash
curl -fsSL uvget.me/install.sh | bash -s -- <package_name>
```

**Windows:**
```powershell
iwr -useb uvget.me/install.ps1 -OutFile install.ps1; .\install.ps1 <package_name>
```

## Examples

```bash
# HTTPie
curl -fsSL uvget.me/install.sh | bash -s -- httpie

# AlgoKit  
curl -fsSL uvget.me/install.sh | bash -s -- algokit

# With Python
curl -fsSL uvget.me/install.sh | bash -s -- --with-python black
```

## Options

| Flag | Description |
|------|-------------|
| `--help` | Show usage |
| `--with-python` | Install Python if needed |
| `--dry-run` | Preview without changes |

## License

MIT
