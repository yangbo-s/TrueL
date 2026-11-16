#!/usr/bin/env python3
"""Check captured window artifacts; component alignment also needs visual review."""
import json, struct, sys
from pathlib import Path
root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / 'artifacts/screenshots'
records = json.loads((root / 'captures.json').read_text())
surfaces = {'selection-result', 'selection-empty', 'selection-copied', 'selection-error', 'popup-input', 'popup-pinned', 'popup-result', 'popup-copied', 'popup-wide', 'popup-translation', 'popup-translation-long',
            'popup-perfect', 'popup-multiple', 'popup-long', 'popup-indented',
            'settings-general', 'settings-service', 'settings-shortcuts', 'settings-icons', 'settings-about'}
surfaces.update({'popup-empty', 'popup-placeholder-match', 'popup-processing', 'popup-resized', 'selection-processing',
                 'settings-long-model', 'settings-unconfigured', 'settings-service-error',
                 'settings-recording', 'settings-shortcut-error', 'settings-wide'})
if '--toolbar' in sys.argv[2:]:
    surfaces = {f'toolbar-{provider}' for provider in ('openAI', 'claude', 'gemini', 'grok', 'deepSeek', 'kimi', 'glm', 'unconfigured')}
if '--about' in sys.argv[2:]:
    surfaces = {'settings-about'}
if '--icons' in sys.argv[2:]:
    surfaces = {f'settings-icon-{style}' for style in ('1A', '1B', '1C', '3A', '3B', '3C', 'default')}
if '--alignment' in sys.argv[2:]:
    surfaces = {f'alignment-{mode}-{size}-{position}'
                for mode in ('grammar', 'translation')
                for size, positions in [('compact', ('top', 'middle', 'bottom')), ('wide', ('top',))]
                for position in positions}
if '--workflows' in sys.argv[2:]:
    surfaces = {f'quick-{mode}-{state}' for mode in ('grammar', 'translation')
                for state in ('loading', 'result', 'style', 'readonly')}
    surfaces |= {f'workspace-{mode}-{state}' for mode in ('grammar', 'translation') for state in ('result', 'style')}
    surfaces |= {'quick-empty', 'quick-error'}
if '--translation-streaming' in sys.argv[2:]:
    surfaces = {f'{presentation}-translation-{state}' for presentation in ('quick', 'workspace')
                for state in ('streaming', 'result')}
expected = {f'{surface}-{appearance}' for surface in surfaces for appearance in ('light', 'dark')}
assert len(records) == len(expected), 'Expected both appearances of every result and settings surface'
assert {record['name'] for record in records} == expected, 'Missing or duplicate capture states'
panel_ids = {record['windowNumber'] for record in records if not record['name'].startswith('settings-')}
assert len(panel_ids) == (0 if any(flag in sys.argv[2:] for flag in ('--about', '--icons')) else 1), 'Translation and grammar must share one actual window'
for record in records:
    if '--workflows' in sys.argv[2:] or '--translation-streaming' in sys.argv[2:]:
        quick = record['name'].startswith('quick-')
        assert record['presentation'] == ('quick' if quick else 'workspace')
        assert record['scrollCount'] == ('1' if quick else '2'), f'{record["name"]}: unexpected scroll/editor count'
        if '-loading-' in record['name']:
            assert record['isProcessing'] == 'true' and record['returnAction'] == 'none', 'Loading fixture was cancelled'
        if '-streaming-' in record['name']:
            assert record['isProcessing'] == 'true' and record['hasResult'] == 'false', 'Partial output became actionable'
            assert int(record['outputCharacters']) > 0 and record['returnAction'] == 'none', 'Streaming text was not visible'
        if record['name'].startswith('quick-error-'):
            assert record['canSubmit'] == 'true' and record['hasResult'] == 'false', 'Error fixture must retain source for retry'
        if quick and any(f'-{state}-' in record['name'] for state in ('result', 'style', 'readonly')):
            assert record['returnAction'] == 'replace' and record['focus'] == 'result'
    if '--alignment' in sys.argv[2:]:
        styles = record['scrollStyles'].split(',')
        assert len(styles) == 2 and styles[0] == styles[1], f'{record["name"]}: inconsistent native scrollers'
    if '--icons' in sys.argv[2:]:
        expected_icon = record['name'].split('-')[2]
        if expected_icon == 'default': expected_icon = '3A'
        assert record['selectedAppIcon'] == expected_icon, 'Unexpected selected icon'
        assert record['appliedAppIcon'] == expected_icon, 'Selected icon did not reach the runtime controller'
    assert record['visibleContentWindows'] == '1', f'{record["name"]}: overlapping content windows'
    assert record['nativeWindowControls'] == '3', f'{record["name"]}: native traffic lights missing or disabled'
    assert record['headerWithinWindow'] == 'true', f'{record["name"]}: header was clipped outside the actual viewport'
    path = Path(record['path'])
    raw = path.read_bytes()
    assert raw[:8] == b'\x89PNG\r\n\x1a\n', path
    w, h = struct.unpack('>II', raw[16:24])
    scale = w / float(record['width'])
    assert scale in (1, 2), f'{path}: unexpected horizontal scale'
    assert abs(h - float(record['height']) * scale) <= 2, f'{path}: inconsistent image bounds'
    assert record['keyWindow'] == 'true', f'{path}: window was inactive'
    assert record['method'] == 'window-screencapture', f'{path}: material capture unavailable'
print(f'PASS {len(records)} active window captures; dimensions, scale and capture method verified')
