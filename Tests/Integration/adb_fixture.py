#!/opt/homebrew/bin/python3
# Test-only ADB and scrcpy-server protocol fixture; never touches a real device.
import json, pathlib, socket, struct, sys, threading, time
root=pathlib.Path(__file__).resolve().parent.parent
args=sys.argv[1:]
with (root/'commands.jsonl').open('a') as log:
    log.write(json.dumps(args)+'\n')
if args and args[0]=='-s':
    serial=args[1]; args=args[2:]
else:
    serial=''
if args==['devices','-l']:
    print('List of devices attached\nfixture-one device usb:1 model:Fixture_One transport_id:1\nfixture-two device usb:2 model:Fixture_Two transport_id:2')
elif args and args[0]=='reverse' and args[1]!='--remove':
    (root/args[1].split(':')[1]).write_text(args[2].split(':')[1])
elif args and args[0]=='shell' and 'com.genymobile.scrcpy.Server' in args:
    scid=next(a.split('=')[1] for a in args if a.startswith('scid='))
    port=int((root/('scrcpy_'+scid)).read_text())
    def connect():
        for i in range(100):
            try: return socket.create_connection(('127.0.0.1',port))
            except ConnectionRefusedError: time.sleep(.02)
        raise RuntimeError('client did not listen')
    video=connect(); audio=connect(); control=connect()
    video.sendall(('Fixture '+serial).encode().ljust(64,b'\0'))
    video.sendall(b'h264'+struct.pack('>III',0x80000000,360,780))
    audio.sendall(b'\0'*4)
    def receive():
        try:
            while data:=control.recv(8192):
                with (root/'control.bin').open('ab') as out: out.write(data)
        except OSError: pass
    threading.Thread(target=receive,daemon=True).start()
    data=(root/'video.h264').read_bytes()
    packets=json.loads((root/'packets.json').read_text())['packets']
    try:
        for i in range(36000):
            packet=packets[i%len(packets)]
            pos=int(packet['pos']);size=int(packet['size'])
            frame=data[pos:pos+size]
            video.sendall(struct.pack('>QI',(1<<61)+i*100000,len(frame))+frame)
            time.sleep(.1)
    except (BrokenPipeError,ConnectionResetError): pass
