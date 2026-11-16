import argparse
import base64
import os
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--clean', action='store_true')
options = parser.parse_args()
runner_temp = os.environ.get('RUNNER_TEMP')
if not runner_temp:
    raise SystemExit('此脚本用于 GitHub Actions；本机构建请配置 android/key.properties。')

temp = Path(runner_temp)
release_key = temp / 'duanju-release.jks'
debug_key = temp / 'duanju-debug-test.jks'
properties_file = root / 'android' / 'key.properties'

if options.clean:
    release_key.unlink(missing_ok=True)
    debug_key.unlink(missing_ok=True)
    properties_file.unlink(missing_ok=True)
    raise SystemExit(0)

names = ['ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD',
         'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD']
values = [os.environ.get(name, '') for name in names]

if all(values):
    try:
        data = base64.b64decode(''.join(values[0].split()), validate=True)
    except ValueError:
        raise SystemExit('ANDROID_KEYSTORE_BASE64 不是有效的 Base64。')
    if not data:
        raise SystemExit('Android 签名文件为空。')
    release_key.write_bytes(data)
    release_key.chmod(0o600)
    store_file = release_key
    store_password, key_alias, key_password = values[1], values[2], values[3]
    print('已配置固定 Android 发布签名。')
else:
    # Disposable CI key: suitable for installing a test APK, not production updates.
    subprocess.run([
        'keytool', '-genkeypair', '-noprompt',
        '-keystore', str(debug_key),
        '-storepass', 'android',
        '-keypass', 'android',
        '-alias', 'androiddebugkey',
        '-keyalg', 'RSA',
        '-keysize', '2048',
        '-validity', '10000',
        '-dname', 'CN=Android Debug,O=Android,C=US',
    ], check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    debug_key.chmod(0o600)
    store_file = debug_key
    store_password, key_alias, key_password = 'android', 'androiddebugkey', 'android'
    print('PERINGATAN: APK ditandatangani dengan kunci debug sementara untuk pengujian; bukan rilis produksi.')

def escape(value):
    result = ''
    for character in value:
        if character in '\\:=#! ':
            result += '\\' + character
        elif character == '\n':
            result += '\\n'
        elif character == '\r':
            result += '\\r'
        elif character == '\t':
            result += '\\t'
        elif ord(character) > 126:
            encoded = character.encode('utf-16-be')
            result += ''.join('\\u' + encoded[i:i + 2].hex() for i in range(0, len(encoded), 2))
        else:
            result += character
    return result

properties = {
    'storeFile': store_file.as_posix(),
    'storePassword': store_password,
    'keyAlias': key_alias,
    'keyPassword': key_password,
}
properties_file.write_text(
    ''.join(f'{name}={escape(value)}\n' for name, value in properties.items()),
    encoding='ascii',
)
properties_file.chmod(0o600)
