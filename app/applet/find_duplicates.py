import os
import re

def find_duplicate_imports(directory):
    for root, dirs, files in os.walk(directory):
        if 'node_modules' in dirs:
            dirs.remove('node_modules')
        for file in files:
            if file.endswith('.tsx') or file.endswith('.ts'):
                path = os.path.join(root, file)
                with open(path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    matches = re.findall(r'import\s+\{([^}]+)\}\s+from\s+["\']([^"\']+)["\']', content)
                    imports = {}
                    for named_imports, source in matches:
                        items = [i.strip() for i in named_imports.split(',')]
                        for item in items:
                            if item in imports and imports[item] != source:
                                print(f"CONFLICT in {path}: {item} imported from {imports[item]} and {source}")
                            elif item in imports and imports[item] == source:
                                print(f"DUPLICATE in {path}: {item} imported twice from {source}")
                            imports[item] = source

find_duplicate_imports('src')
