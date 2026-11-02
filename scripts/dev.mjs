import { spawn } from 'node:child_process';
import process from 'node:process';

const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
const children = [
  spawn(npm, ['run', 'dev', '--workspace', 'client'], { stdio: 'inherit', shell: process.platform === 'win32' }),
  spawn(npm, ['run', 'dev', '--workspace', 'server'], { stdio: 'inherit', shell: process.platform === 'win32' })
];
const stop = () => children.forEach(child => child.kill());
process.on('SIGINT', stop); process.on('SIGTERM', stop);
children.forEach(child => child.on('exit', code => { if (code && code !== 130) process.exitCode = code; }));
