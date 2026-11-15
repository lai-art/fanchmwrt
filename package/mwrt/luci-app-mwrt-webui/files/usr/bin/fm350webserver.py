n='ERROR'
i='MODE'
c=KeyboardInterrupt
V=True
h='direct'
g='tom_modem'
S='HOST'
R='SERIAL'
f=isinstance
a='无返回'
Z=None
P='HTTP'
Y=b''
O='WEBSOCKET'
U='OK'
T=range
G=len
E='PORT'
N=str
M=print
K=Exception
I=False
H='ignore'
import asyncio as C,websockets as j,json as F,os as D,sys,threading as k,http.server,socketserver as o,subprocess as p,logging as A,glob,serial as d,binascii as q,re
A.basicConfig(level=A.INFO,format='%(asctime)s %(levelname)s %(message)s')
A.getLogger().setLevel(A.ERROR)
Q=D.path.join(D.path.dirname(D.path.abspath(__file__)),'config.json')
def r():
	J='utf-8';B={O:{S:'0.0.0.0',E:8766},P:{E:8001},R:{E:'/dev/ttyUSB1',i:g}}
	if not D.path.exists(Q):
		with open(Q,'w',encoding=J)as G:F.dump(B,G,indent=4,ensure_ascii=I)
		return B
	with open(Q,'r',encoding=J)as G:C=F.load(G)
	for A in B:
		if A not in C:C[A]=B[A]
		else:
			for H in B[A]:
				if H not in C[A]:C[A][H]=B[A][H]
	return C
B=r()
e=B[R][i]
W=B[R][E]
J=Z
def s():
	D='AT';import time,serial.tools.list_ports;E=[A.device for A in serial.tools.list_ports.comports()]
	for B in E:
		try:
			if e==h:
				C=serial.Serial(B,115200,timeout=2);C.reset_input_buffer();C.write(b'AT\r');time.sleep(.5);F=C.read_all().decode(errors=H);C.close()
				if D in F:A.info(f"[direct模式] 检测到AT端口: {B}");return B
			else:
				G=p.run([g,B,'-c',D],capture_output=V,timeout=2);I=G.stdout.decode(errors=H)
				if D in I:A.info(f"检测到AT端口: {B}");return B
		except K as J:A.info(f"检测端口{B}失败: {J}");continue
if W=='auto':J=s()
else:J=W
if not J:M('未检测到AT端口，程序退出');sys.exit(1)
l=set()
m=C.Lock()
async def t(args):
	o='串口异常';n='+CMS ERROR:';l='短信发送成功';k='+CMGS:';j=b'\x1a';i='收到 > 提示符，准备发送PDU数据';g='AT+CMGF=0 未返回OK';f='发送: AT+CMGF=0';c=b'AT+CMGF=0\r';b='\\D';O='未收到 > 提示符，模块无响应';N=args;import re
	if G(N)<3:A.error('参数不足，格式应为 SEND_SMS,短信中心号码手机号,"短信内容"');return'参数不足，格式应为 SEND_SMS,手机号,"短信内容"'
	p=N[1].strip();R=N[2].strip();S=N[3].strip('"');A.info(f"准备发送短信: 手机号={R}, 内容={S}")
	def V(number):
		A=number;A=re.sub(b,'',A)
		if G(A)%2!=0:A+='F'
		B=''
		for C in T(0,G(A),2):B+=A[C+1]+A[C]
		return B
	def r(text):return q.hexlify(text.encode('utf-16-be')).decode().upper()
	W=V(p);s=int(G(W)/2+1);t=f"{s:02X}91{W}";u='11';v='00';X=re.sub(b,'',R);w=f"{G(X):02X}91{V(X)}";x='00';y='08';Z=r(S);z=f"{G(Z)//2:02X}";A0='a7'+z+Z;a=u+v+w+x+y+A0;I=t+a;L=G(a)//2;A.info(f"PDU编码: {I}");A.info(f"AT+CMGS长度: {L}")
	try:
		if e==h:
			async with m:
				try:
					with d.Serial(J,115200,timeout=5)as B:
						A.info(f"[direct模式] 新建串口: {J}");B.write(c);A.info(f);await C.sleep(.5);M=B.read_all().decode(errors=H);A.info(f"AT+CMGF=0 返回: {M}")
						if U not in M:return g
						B.write(f"AT+CMGS={L}\r".encode());A.info(f"发送: AT+CMGS={L}");F=Y
						for P in T(30):
							await C.sleep(.1);E=B.read_all()
							if E:A.info(f"收到串口数据: {E}")
							F+=E
							if b'>'in F:A.info(i);break
						else:A.error(O);return O
						B.write(I.encode()+j);A.info(f"发送PDU+Ctrl+Z: {I}");F=Y
						for P in T(100):
							await C.sleep(.1);E=B.read_all()
							if E:A.info(f"收到串口数据: {E}")
							F+=E;D=F.decode(errors=H)
							if k in D:A.info(f"串口返回: {D}");A.info(l);return U
							elif n in D:A.info(f"串口返回: {D}");A.error(f"发送失败: {D}");return f"SEND_FAIL: {D}"
						A.warning(f"未知返回: {D}");return f"ERROR: {D}"
				except K as Q:A.exception(o);return f"串口异常: {Q}"
		else:
			B=d.Serial(J,115200,timeout=5);A.info(f"打开串口: {J}");B.write(c);A.info(f);await C.sleep(.5);M=B.read_all().decode(errors=H);A.info(f"AT+CMGF=0 返回: {M}")
			if U not in M:B.close();return g
			B.write(f"AT+CMGS={L}\r".encode());A.info(f"发送: AT+CMGS={L}");F=Y
			for P in T(30):
				await C.sleep(.1);E=B.read_all()
				if E:A.info(f"收到串口数据: {E}")
				F+=E
				if b'>'in F:A.info(i);break
			else:B.close();A.error(O);return O
			B.write(I.encode()+j);A.info(f"发送PDU+Ctrl+Z: {I}");F=Y
			for P in T(100):
				await C.sleep(.1);E=B.read_all()
				if E:A.info(f"收到串口数据: {E}")
				F+=E;D=F.decode(errors=H)
				if k in D:A.info(f"串口返回: {D}");B.close();A.info(l);return U
				elif n in D:A.info(f"串口返回: {D}");B.close();A.error(f"发送失败: {D}");return f"SEND_FAIL: {D}"
			B.close();A.warning(f"未知返回: {D}");return f"ERROR: {D}"
	except K as Q:A.exception(o);return f"串口异常: {Q}"
async def u(cmd):
	try:
		D=re.match('^\\s*CMD\\((.*)\\)\\s*$',cmd.strip(),re.DOTALL)
		if not D:return'CMD 语法错误，应为 CMD(<command>)\nERROR'
		E=D.group(1).strip();A.info(f"执行系统命令: {E}");B=await C.create_subprocess_shell(E,stdout=C.subprocess.PIPE,stderr=C.subprocess.PIPE)
		try:F,G=await C.wait_for(B.communicate(),timeout=5)
		except C.TimeoutError:B.kill();A.error('系统命令执行超时');return'系统命令执行超时\nERROR'
		I=F.decode(errors=H).strip();J=G.decode(errors=H).strip();L=U if B.returncode==0 else n;M=I or J or a;return f"{M}\n{L}"
	except K as O:A.exception('执行系统命令异常');return f"{N(O)}\nERROR"
async def v(websocket,path=Z):
	p='cmd';k='命令执行超时';j='\r\n';P='result';L='id';E=websocket;M('ws_handler loaded',E,path);l.add(E);M(f"WebSocket客户端已连接: {E.remote_address}")
	try:
		async for b in E:
			B=Z;G=Z
			if f(b,N):
				try:
					R=F.loads(b)
					if f(R,dict)and p in R:G=R[p];B=R.get(L)
					else:G=b.strip()
				except K:G=b.strip()
			else:await E.send(F.dumps({'error':'不支持二进制消息'},ensure_ascii=I));continue
			if not G:continue
			if f(G,N)and G.strip().startswith('CMD('):S=await u(G);D={L:B,P:S}if B else S;A.info(f"系统命令返回: {D}");await E.send(F.dumps(D,ensure_ascii=I)if B else S);continue
			if G.startswith('SEND_SMS'):q=G.split(',',3);S=await t(q);D={L:B,P:S}if B else S;A.info(f"发送短信返回: {D}");await E.send(F.dumps(D,ensure_ascii=I)if B else S);continue
			if not G.endswith('\r')and not G.endswith('\n'):G+='\r'
			V=G
			if e==h:
				async with m:
					try:
						with d.Serial(J,115200,timeout=5)as c:
							c.reset_input_buffer();c.reset_output_buffer()
							if not V.endswith(j):V=V.rstrip(j)+j
							c.write(V.encode());i=Y
							for v in T(50):
								await C.sleep(.1);R=c.read_all()
								if R:i+=R
								Q=i.decode(errors=H).strip()
								if U in Q or n in Q or'BUSY'in Q:break
							Q=i.decode(errors=H).strip();A.info(f"串口返回: {Q}");D={L:B,P:Q}if B else Q;await E.send(F.dumps(D,ensure_ascii=I)if B else Q)
					except K as O:A.exception('串口命令异常');D={L:B,P:N(O)}if B else N(O);await E.send(F.dumps(D,ensure_ascii=I)if B else N(O))
				continue
			else:
				try:
					A.info(f"调用tom_modem参数: tom_modem {J} -c '{V}'");o=await C.create_subprocess_exec(g,J,'-c',V,stdout=C.subprocess.PIPE,stderr=C.subprocess.PIPE)
					try:r,s=await C.wait_for(o.communicate(),timeout=5)
					except C.TimeoutError:A.error(k);D={L:B,P:k}if B else k;await E.send(F.dumps(D,ensure_ascii=I)if B else D);o.kill();continue
					W=r.decode(errors=H).strip();X=s.decode(errors=H).strip();A.info(f"tom_modem标准输出: {W}");A.info(f"tom_modem标准错误: {X}")
					if W:A.info(f"推送到前端: {W}");D={L:B,P:W}if B else W;await E.send(F.dumps(D,ensure_ascii=I)if B else W)
					elif X:A.info(f"推送到前端: {X}");D={L:B,P:X}if B else X;await E.send(F.dumps(D,ensure_ascii=I)if B else X)
					else:A.info('推送到前端: 无返回');D={L:B,P:a}if B else a;await E.send(F.dumps(D,ensure_ascii=I)if B else a)
				except K as O:A.exception('执行tom_modem命令异常');D={L:B,P:N(O)}if B else N(O);await E.send(F.dumps(D,ensure_ascii=I)if B else N(O))
	except K as O:M(f"WebSocket客户端断开: {O}")
	finally:l.discard(E)
def w():C=D.path.join(D.path.dirname(D.path.abspath(__file__)),'web');D.chdir(C);A=B[P][E]if P in B and E in B[P]else 8001;F=http.server.SimpleHTTPRequestHandler;G=o.TCPServer(('',A),F);M(f"HTTP 服务器已启动: http://0.0.0.0:{A}/");G.serve_forever()
x=k.Thread(target=w,daemon=V)
x.start()
async def y():A=await j.serve(v,B[O][S],B[O][E]);M(f"WebSocket服务器已启动: ws://{B[O][S]}:{B[O][E]}");await A.wait_closed()
if __name__=='__main__':
	try:
		if sys.platform=='win32':C.set_event_loop_policy(C.WindowsSelectorEventLoopPolicy())
		try:L=C.new_event_loop();C.set_event_loop(L)
		except K as X:L=C.get_event_loop()
		try:L.run_until_complete(y())
		except c:M('\n正在关闭服务...')
		finally:
			b=C.all_tasks(L)
			for z in b:z.cancel()
			L.run_until_complete(C.gather(*b,return_exceptions=V));L.close()
	except c:M('主动停止监听短信')
	except K as X:M(f"程序启动错误: {X}")