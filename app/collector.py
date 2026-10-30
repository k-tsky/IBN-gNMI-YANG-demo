"""Real SNMP polling and gNMI ON_CHANGE observations of the same interface."""
import logging
import os
import re
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PATH = '/interface[name=ethernet-1/1]/oper-state'
INTERVAL = float(os.getenv('POLL_SECONDS', '10'))
IFNAME_OID = '.1.3.6.1.2.1.31.1.1.1.1'
OPER_OID = '.1.3.6.1.2.1.2.2.1.8'


def snmp_state(text):
    status = int(text.strip())
    if status not in range(1, 8):
        raise ValueError(f'Invalid ifOperStatus: {status}')
    return int(status == 1)


def interface_index(text):
    for line in text.splitlines():
        match = re.fullmatch(r'\s*' + re.escape(IFNAME_OID) + r'\.(\d+)\s*=\s*"?ethernet-1/1"?\s*', line)
        if match:
            return int(match[1])
    raise ValueError('ethernet-1/1 not found in SNMP ifName table')


def snmp_read(index=None):
    host = os.getenv('GNMI_HOST', 'clab-telemetry-srl')
    common = ['-m', '', '-v2c', '-c', 'telemetrylab', '-t', '2', '-r', '0']
    if index is None:
        walk = subprocess.check_output(['snmpwalk', *common, '-On', '-OQ', host, IFNAME_OID],
                                       text=True, timeout=6)
        index = interface_index(walk)
        # SR Linux 24.10 initializes its ifTable lazily: walk it once before
        # issuing direct Get requests, otherwise a cold agent returns noSuchInstance.
        subprocess.check_output(['snmpwalk', *common, '-On', host, OPER_OID],
                                text=True, timeout=6)
    value = subprocess.check_output(['snmpget', *common, '-Oqv', '-Oe', host, f'{OPER_OID}.{index}'],
                                    text=True, timeout=6)
    return index, snmp_state(value)


def observation(message):
    notifications = message.get('notification', [])
    if isinstance(message.get('update'), dict):
        notifications = [message['update']]
    for notification in notifications:
        for update in notification.get('update', []):
            value = update.get('val')
            if value in ('up', 'down'):
                return int(value == 'up')
    return None


class Observations:
    def __init__(self):
        self.lock = threading.RLock()
        self.data = {m: dict(value=None, healthy=0, observations=0, downs=0,
                             last=0, errors=0) for m in ('poll', 'stream')}

    def record(self, method, value):
        with self.lock:
            row = self.data[method]
            if value == 0 and row['value'] != 0:
                row['downs'] += 1
            row.update(value=value, healthy=1, last=time.time())
            row['observations'] += 1

    def failed(self, method):
        with self.lock:
            self.data[method]['healthy'] = 0
            self.data[method]['errors'] += 1

    def metrics(self):
        lines = []
        with self.lock:
            for method, row in self.data.items():
                values = {'collector_healthy': row['healthy'],
                          'observations_total': row['observations'],
                          'down_events_total': row['downs'],
                          'last_observation_seconds': row['last'],
                          'errors_total': row['errors']}
                if row['value'] is not None:
                    values['interface_up'] = row['value']
                for name, value in values.items():
                    lines.append(f'demo_{name}{{method="{method}"}} {value}')
        return '\n'.join(lines) + '\n'


DATA = Observations()


def client():
    from pygnmi.client import gNMIclient
    return gNMIclient(target=(os.getenv('GNMI_HOST', 'clab-telemetry-srl'),
                              int(os.getenv('GNMI_PORT', '57400'))),
                      username='admin', password='NokiaSrl1!',
                      insecure=False, skip_verify=True, gnmi_timeout=10)


def poll():
    index = None
    while True:
        started = time.monotonic()
        try:
            index, value = snmp_read(index)
            DATA.record('poll', value)
        except Exception:
            index = None
            logging.exception('SNMP poll failed; retrying')
            DATA.failed('poll')
        time.sleep(max(0.1, INTERVAL - (time.monotonic() - started)))


def next_message(updates):
    if updates.error is not None:
        raise updates.error
    try:
        return updates.get_update(timeout=1)
    except TimeoutError:
        if updates.error is not None:
            raise updates.error
        return None


def stream():
    subscription = {'subscription': [{'path': PATH, 'mode': 'on_change'}],
                    'mode': 'stream', 'encoding': 'json_ietf'}
    while True:
        try:
            with client() as connection:
                updates = connection.subscribe2(subscribe=subscription)
                try:
                    while True:
                        message = next_message(updates)
                        if message is None:
                            continue
                        value = observation(message)
                        if value is not None:
                            DATA.record('stream', value)
                finally:
                    updates.close()
        except Exception:
            logging.exception('Subscription failed; reconnecting')
            DATA.failed('stream')
            time.sleep(2)


class Handler(BaseHTTPRequestHandler):
    def respond(self, status, content, mime):
        body = content.encode()
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == '/metrics':
            self.respond(200, DATA.metrics(), 'text/plain; version=0.0.4')
        else:
            self.respond(404, 'Not found', 'text/plain')

    def log_message(self, *_):
        pass


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    threading.Thread(target=poll, daemon=True).start()
    threading.Thread(target=stream, daemon=True).start()
    ThreadingHTTPServer(('0.0.0.0', 8000), Handler).serve_forever()
