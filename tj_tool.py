#!/usr/bin/env python3
"""
tj_tool.py - TaskJuggler Project Planning Updater & Runner

This tool allows you to programmatically locate and update task attributes in TaskJuggler
(.tjp) files, preserving all comments, indentation, formatting, and structures. It then
runs TaskJuggler (tj3) to schedule and create the project plan.
"""

import re
import sys
import argparse
import subprocess
from typing import List, Dict, Union, Optional

# Token types for lexical analysis
MULTILINE_COMMENT = 'MULTILINE_COMMENT'
COMMENT = 'COMMENT'
STRING = 'STRING'
BRACE = 'BRACE'
WHITESPACE = 'WHITESPACE'
WORD = 'WORD'
OTHER = 'OTHER'

class Token:
    """Represents a single lexical token in a .tjp file."""
    def __init__(self, type_: str, value: str):
        self.type = type_
        self.value = value

    def __repr__(self) -> str:
        return f"Token({self.type}, {repr(self.value)})"


class Block:
    """Represents a braced block in a .tjp file, e.g. task items "..." { ... }."""
    def __init__(self, header: List[Union[Token, 'Block']], open_brace: Token, body: List[Union[Token, 'Block']], close_brace: Optional[Token]):
        self.header = header          # Tokens/Blocks preceding the '{'
        self.open_brace = open_brace  # The '{' Token
        self.body = body              # Inner Tokens/Blocks inside the '{' and '}'
        self.close_brace = close_brace # The '}' Token (None if unmatched)

    def __repr__(self) -> str:
        return f"Block(header={self.header}, body={self.body})"


def tokenize(text: str) -> List[Token]:
    """Tokenizes TaskJuggler source text into a flat list of Token objects."""
    tok_regex = re.compile(
        r'(?P<MULTILINE_COMMENT>/\*[\s\S]*?\*/)'
        r'|(?P<COMMENT>(?:#|//)[^\r\n]*)'
        r'|(?P<STRING>"(?:[^"\\]|\\.)*")'
        r'|(?P<BRACE>[{}])'
        r'|(?P<WHITESPACE>\s+)'
        r'|(?P<WORD>[^\s"{}#]+)'
    )
    tokens = []
    last_end = 0
    for match in tok_regex.finditer(text):
        if match.start() > last_end:
            # Capture any symbol characters not captured by other groups
            val = text[last_end:match.start()]
            tokens.append(Token(OTHER, val))
        
        type_ = match.lastgroup
        val = match.group(type_)
        tokens.append(Token(type_, val))
        last_end = match.end()
        
    if last_end < len(text):
        tokens.append(Token(OTHER, text[last_end:]))
        
    return tokens


def parse_to_tree(tokens: List[Token]) -> List[Union[Token, Block]]:
    """Parses a flat list of tokens into a hierarchical AST of Tokens and Blocks."""
    index = 0
    n = len(tokens)
    
    def parse_list(parent_braced: bool = False) -> List[Union[Token, Block]]:
        nonlocal index
        elements = []
        
        while index < n:
            token = tokens[index]
            if token.type == BRACE and token.value == '{':
                # Determine header from elements accumulated at this level.
                # Look backward for the last newline or block boundary.
                header_start = 0
                for i in range(len(elements) - 1, -1, -1):
                    elem = elements[i]
                    if isinstance(elem, Block):
                        header_start = i + 1
                        break
                    elif isinstance(elem, Token):
                        if elem.type == WHITESPACE and '\n' in elem.value:
                            header_start = i + 1
                            break
                
                header = elements[header_start:]
                elements = elements[:header_start]
                
                open_brace = token
                index += 1
                
                # Parse body of block recursively
                body = parse_list(parent_braced=True)
                
                # Consume closing brace
                if index < n and tokens[index].type == BRACE and tokens[index].value == '}':
                    close_brace = tokens[index]
                    index += 1
                else:
                    close_brace = None
                
                block = Block(header, open_brace, body, close_brace)
                elements.append(block)
                
            elif token.type == BRACE and token.value == '}':
                if parent_braced:
                    # Return back to parent block parser (let caller consume '}')
                    break
                else:
                    # Unmatched '}' at top-level
                    elements.append(token)
                    index += 1
            else:
                elements.append(token)
                index += 1
                
        return elements

    return parse_list()


def reconstruct(elements: List[Union[Token, Block]]) -> str:
    """Reconstructs the source text from the AST elements with 100% round-trip fidelity."""
    result = []
    for elem in elements:
        if isinstance(elem, Token):
            result.append(elem.value)
        elif isinstance(elem, Block):
            result.append(reconstruct(elem.header))
            result.append(elem.open_brace.value)
            result.append(reconstruct(elem.body))
            if elem.close_brace:
                result.append(elem.close_brace.value)
    return "".join(result)


def find_task(elements: List[Union[Token, Block]], path_parts: List[str]) -> Optional[Dict]:
    """
    Finds a task by its dot-separated ID path in the AST.
    Returns metadata about the task if found, including its type, parent list, and index.
    """
    if not path_parts:
        return None
    
    target_id = path_parts[0]
    
    i = 0
    while i < len(elements):
        elem = elements[i]
        
        # Scenario 1: Task defined with a block { ... }
        if isinstance(elem, Block):
            header_tokens = [t for t in elem.header if isinstance(t, Token) and t.type not in (WHITESPACE, COMMENT, MULTILINE_COMMENT)]
            if len(header_tokens) >= 2 and header_tokens[0].value.lower() == 'task':
                task_id = header_tokens[1].value
                if task_id == target_id:
                    if len(path_parts) == 1:
                        return {"type": "block", "block": elem, "parent_list": elements, "index": i}
                    else:
                        return find_task(elem.body, path_parts[1:])
            i += 1
            continue
            
        # Scenario 2: Task defined as a single-line statement (no block)
        elif isinstance(elem, Token):
            if elem.type == WORD and elem.value.lower() == 'task':
                stmt_tokens = [elem]
                j = i + 1
                
                # Consume statement tokens until hitting next block, newline or statement boundary
                while j < len(elements):
                    next_elem = elements[j]
                    if isinstance(next_elem, Block):
                        break
                    if isinstance(next_elem, Token):
                        if next_elem.type == WHITESPACE and '\n' in next_elem.value:
                            break
                        stmt_tokens.append(next_elem)
                    j += 1
                
                non_ws = [t for t in stmt_tokens if t.type not in (WHITESPACE, COMMENT, MULTILINE_COMMENT)]
                if len(non_ws) >= 2:
                    task_id = non_ws[1].value
                    task_name = non_ws[2].value if len(non_ws) >= 3 and non_ws[2].type == STRING else None
                    
                    if task_id == target_id:
                        if len(path_parts) == 1:
                            return {
                                "type": "statement",
                                "tokens": stmt_tokens,
                                "id": task_id,
                                "name": task_name,
                                "parent_list": elements,
                                "start_index": i,
                                "end_index": j
                            }
                        else:
                            # A non-block task statement cannot have subtasks
                            return None
                i = j
                continue
        i += 1
    return None


def update_task_attributes(task_info: Dict, attrs: Dict[str, str]) -> None:
    """Updates or adds attributes within the specified task block or statement."""
    if task_info["type"] == "block":
        block = task_info["block"]
        body = block.body
        
        # Determine internal indentation of the block body
        indent = "  "
        for elem in body:
            if isinstance(elem, Token) and elem.type == WHITESPACE and '\n' in elem.value:
                parts = elem.value.split('\n')
                if parts[-1]:
                    indent = parts[-1]
                    break
        else:
            # Fallback to header indentation plus 2 spaces
            header = block.header
            for elem in header:
                if isinstance(elem, Token) and elem.type == WHITESPACE and '\n' in elem.value:
                    parts = elem.value.split('\n')
                    indent = parts[-1] + "  "
                    break
        
        for key, val in attrs.items():
            # Check if key already exists directly within this block
            key_index = -1
            for idx, elem in enumerate(body):
                if isinstance(elem, Token) and elem.type == WORD and elem.value.lower() == key.lower():
                    key_index = idx
                    break
            
            if key_index != -1:
                # Key exists. Find where the value tokens end.
                end_val_idx = key_index + 1
                while end_val_idx < len(body):
                    t = body[end_val_idx]
                    if isinstance(t, Block):
                        break
                    if isinstance(t, Token):
                        if t.type == WHITESPACE and '\n' in t.value:
                            break
                        if t.type in (COMMENT, MULTILINE_COMMENT):
                            break
                    end_val_idx += 1
                
                # Replace value tokens
                body[key_index + 1 : end_val_idx] = [Token(WHITESPACE, ' '), Token(WORD, str(val))]
            else:
                # Key does not exist. Insert at the end of block's body.
                if body and isinstance(body[-1], Token) and body[-1].type == WHITESPACE and '\n' in body[-1].value:
                    body.insert(-1, Token(WHITESPACE, '\n' + indent))
                    body.insert(-1, Token(WORD, key))
                    body.insert(-1, Token(WHITESPACE, ' '))
                    body.insert(-1, Token(WORD, str(val)))
                else:
                    new_tokens = [
                        Token(WHITESPACE, '\n' + indent),
                        Token(WORD, key),
                        Token(WHITESPACE, ' '),
                        Token(WORD, str(val)),
                        Token(WHITESPACE, '\n')
                    ]
                    body.extend(new_tokens)
                    
    elif task_info["type"] == "statement":
        # Convert statement task to block task
        parent_list = task_info["parent_list"]
        start_idx = task_info["start_index"]
        end_idx = task_info["end_index"]
        stmt_tokens = task_info["tokens"]
        
        header = list(stmt_tokens)
        while header and isinstance(header[-1], Token) and header[-1].type == WHITESPACE:
            header.pop()
        header.append(Token(WHITESPACE, ' ')) # ensure space before brace
            
        # Determine parent indentation
        indent = "  "
        for elem in reversed(parent_list[:start_idx]):
            if isinstance(elem, Token) and elem.type == WHITESPACE and '\n' in elem.value:
                parts = elem.value.split('\n')
                indent = parts[-1] + "  "
                break
        
        body = []
        for key, val in attrs.items():
            body.extend([
                Token(WHITESPACE, '\n' + indent),
                Token(WORD, key),
                Token(WHITESPACE, ' '),
                Token(WORD, str(val))
            ])
        parent_indent = indent[:-2] if len(indent) >= 2 else ""
        body.append(Token(WHITESPACE, '\n' + parent_indent))
        
        block = Block(
            header=header,
            open_brace=Token(BRACE, '{'),
            body=body,
            close_brace=Token(BRACE, '}')
        )
        parent_list[start_idx:end_idx] = [block]


def run_taskjuggler(tjp_file: str) -> bool:
    """Runs TaskJuggler (tj3) on the specified .tjp file and prints its output."""
    print(f"\n>>> Running TaskJuggler (tj3) on {tjp_file}...")
    try:
        result = subprocess.run(["tj3", tjp_file], capture_output=True, text=True)
        print(result.stdout)
        if result.stderr:
            print("Error details (stderr):")
            print(result.stderr)
        if result.returncode == 0:
            print(">>> TaskJuggler execution completed successfully!")
            return True
        else:
            print(f">>> TaskJuggler failed with return code {result.returncode}")
            return False
    except FileNotFoundError:
        print(">>> Error: 'tj3' command not found. Please ensure TaskJuggler is installed.")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="TaskJuggler Project Planning Updater & Runner. Programmatically edit task attributes and run tj3."
    )
    parser.add_argument("tjp_file", help="Path to the TaskJuggler (.tjp) file")
    parser.add_argument("-t", "--task", help="Dot-separated ID path to the task (e.g. 'product.s1.t1')")
    parser.add_argument("-s", "--set", action="append", help="Attribute to update/add in format key=value (e.g., 'effort=10d')")
    parser.add_argument("-o", "--output", help="Path to write the updated file (defaults to updating in-place)")
    parser.add_argument("-r", "--run", action="store_true", help="Execute TaskJuggler (tj3) to create/update the plan")

    args = parser.parse_args()

    # Read and parse tjp file
    try:
        with open(args.tjp_file, 'r') as f:
            content = f.read()
    except Exception as e:
        print(f"Error reading file '{args.tjp_file}': {e}")
        sys.exit(1)

    tokens = tokenize(content)
    tree = parse_to_tree(tokens)

    # Perform updates if task and attributes are specified
    file_modified = False
    if args.task:
        if not args.set:
            print("Error: You must specify attributes to set using -s/--set when -t/--task is specified.")
            sys.exit(1)
        
        # Parse set key-values
        attrs = {}
        for kv in args.set:
            if '=' not in kv:
                print(f"Error: Invalid set attribute '{kv}'. Must be in format key=value.")
                sys.exit(1)
            k, v = kv.split('=', 1)
            attrs[k.strip()] = v.strip()

        # Find target task
        path_parts = args.task.split('.')
        task_info = find_task(tree, path_parts)
        if not task_info:
            print(f"Error: Task '{args.task}' not found in the project planning file.")
            sys.exit(1)

        print(f"Updating task '{args.task}' with attributes: {attrs}")
        update_task_attributes(task_info, attrs)
        file_modified = True

    # Output file path selection
    output_file = args.output if args.output else args.tjp_file

    if file_modified:
        updated_content = reconstruct(tree)
        try:
            with open(output_file, 'w') as f:
                f.write(updated_content)
            print(f"Saved updated project planning to '{output_file}'.")
        except Exception as e:
            print(f"Error writing to file '{output_file}': {e}")
            sys.exit(1)

    # Run TaskJuggler planner
    if args.run:
        success = run_taskjuggler(output_file)
        if not success:
            sys.exit(1)


if __name__ == "__main__":
    main()
