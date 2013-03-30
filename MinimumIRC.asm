.386
.MODEL flat,stdcall
OPTION casemap:none
;Inclusions needed
Include WINDOWS.INC
Include KERNEL32.INC
Include USER32.INC
Include WSOCK32.INC
Include MASM32.INC

;Libraries needed
Includelib KERNEL32.lib
Includelib USER32.lib
Includelib WSOCK32.lib
Includelib MASM32.lib


;Structure for a connecton
SOCKaddr_IN Struct
	sin_family	WORD	?
	sin_port	WORD	?
	sin_addr	DWORD	?
	sin_zero	BYTE	8 DUP (?)
SOCKaddr_IN ends
CRLF       TEXTEQU < 13, 10 > ;This is what the end of a line looks like
Port equ 6667 ;Connection Port
WM_SOCKET       equ	WM_USER + 100 ;Socket addr


.DATA
	;Socket variables
	g_hInstance	DWORD NULL
	g_hThread	DWORD NULL
	g_locked	DWORD NULL
	dwSocket	DWORD NULL
	saiClient	SOCKaddr_IN <>
	wsaClient	WSADATA <>
	;End socket variables
	
	;User variables
	szBotName	BYTE	"TheRobot", 0
	szChannel	BYTE	"#fishhat", 0
	szServer    BYTE 	"irc.uk.mibbit.net",0
	;End user variables
	
	szAuth1		BYTE	"NICK %s", 0DH, "USER %s 0 0 :%s", 0AH, 0DH, 0AH, 0DH, 0 ;Set IRC nick
	szPrvMsg	BYTE	"PRIVMSG %s :%s", 0AH, 0DH, 0 ;Send IRC message

	szAboutcmd  BYTE    "!about",0 ;Example command
	szAbout		BYTE    "I am a bot written in MASM",0 ;Command reply
	g_CurrentChan	BYTE ( 200 ) DUP ( NULL ) ;Buffer to hold current channel name
	commandbuf      BYTE ( 2000 ) DUP ( NULL ) ;Buffer for parsing commands
	parsedbuf    BYTE ( 200) DUP ( NULL ) ;Command name
.data?
;Nothing required for now
.CODE
InitSocket PROC ;Socket startup
	Invoke	WSAStartup, 101H, addr wsaClient ;WinSockaddress startup
	cmp	eax, 0
	jne	@@eret
	Invoke	socket, AF_INET, SOCK_STREAM, IPPROTO_TCP ;Set TCP protocol
	mov	dwSocket, eax
	cmp	eax, 0 ;Did it work?
	je	@@eret ;Jump if it didnt work
	xor	eax, eax
	ret
@@eret:	mov	eax, -1 ;basic error checking
	ret
InitSocket endp
ConnectTo PROC lpszHost:DWORD, iPort:DWORD ;connect to a given address using a given port
	Invoke	gethostbyname, lpszHost ;Get IPV4 from hostname
	cmp	eax, 0
	je	@@eret
	mov	eax, [eax + 12]
	mov	eax, [eax]
	mov	eax, [eax]
	mov	saiClient.sin_addr, eax
	Invoke	htons, iPort ;Set the port in the socket
	mov	saiClient.sin_port, AX
	mov	saiClient.sin_family, AF_INET
	Invoke	connect, dwSocket, addr saiClient, SIZEOF SOCKaddr_IN ;Connect using set parameters
	cmp	eax, 0 ;Did it work?
	jne	@@eret ;Jump if it didnt work
	xor	eax, eax
	ret
@@eret:	mov	eax, -1 ;basic error checking
	ret
ConnectTo endp
Disconnect PROC ;Clean up the socket and disconnect, not used but you want this if you plan to reconnect later
	Invoke	closesocket, dwSocket
	Invoke	WSACleanup
	xor	eax, eax
	ret
Disconnect endp
IRCLogin PROC
LOCAL	szBuffer[2025]:BYTE
	Invoke	recv, dwSocket, addr szBuffer, 2024, 0 ;Receive from socket
	Invoke	wsprintf, addr szBuffer, offset szAuth1, offset szBotName, offset szBotName, offset szBotName ;Concat together login string
	Invoke	lstrlen, addr szBuffer ;Get length of Login string
	Invoke	send, dwSocket, addr szBuffer, eax, 0 ;Send login string
	lea	edi, szBuffer
	mov	ecx, 2025
	@@clsa:	mov	BYTE PTR [edi], 0
		dec	ecx
		inc	edi
		cmp	ecx, 0
	jne	@@clsa
@@:	Invoke	recv, dwSocket, addr szBuffer, 2024, 0 ;Receive next packet
	lea	edi, szBuffer
	mov	ecx, eax
	@@ps:	mov	eax, DWORD PTR [edi]
		cmp	eax, 'GNIP' ;They sent GNIP (PING backwards), this means it worked
		je	@@png
		inc	edi
		dec	ecx
		cmp	ecx, 0
	jne	@@ps
	jmp	@B
@@png:	mov	DWORD PTR [edi], 'GNOP';Reply with GNOP (PONG backwards)
	push	edi
		Invoke	lstrlen, edi
	pop	edi
	Invoke	send, dwSocket, edi, eax, 0
	Invoke	recv, dwSocket, addr szBuffer, 2024, 0
	lea	edi, szBuffer
	mov	ecx, 2025
	@@clsb:	mov	BYTE PTR [edi], 0
		dec	ecx
		inc	edi
		cmp	ecx, 0
	jne	@@clsb
	ret
IRCLogin endp
IRCJoin PROC lpszChannel:DWORD ;Join a given IRC Channel
LOCAL	szBuffer[2025]:BYTE
.DATA
	szJoin	BYTE	"JOIN %s ", 0AH, 0DH, 0 ;PrintF style string for joining channel %s
.CODE
	Invoke	wsprintf, addr szBuffer, offset szJoin, lpszChannel ;Create join channel
	Invoke	lstrlen, addr szBuffer
	Invoke	send, dwSocket, addr szBuffer, eax, 0 ;Join channel
	ret
IRCJoin endp
GetWord proc string:DWORD,wrd:DWORD,brk:BYTE,buff:DWORD,buffsize:DWORD ;Splitting up strings example, borrowed from http://tinyurl.com/d8gunp4

LOCAL rett:DWORD
	pushad
	.if string!=0 && buff!=0
		xor edx,edx;edx=wordcnt
		mov esi,string
		mov bl,[esi]
		call skipBrk
		.while bl!=0
			.if bl==brk
				inc edx
				call skipBrk
			.endif
			.break .if edx==wrd || bl==0
			inc esi
			mov bl,[esi]
		.endw
	.if bl!=0
		mov edi,buff
		xor ecx,ecx
		dec buffsize
		.while bl!=0 && bl!=brk && ecx<buffsize
			mov bl,[esi]
			mov [edi],bl
			inc ecx
			inc esi
			inc edi
		.endw
		dec ecx
		mov byte ptr [edi-1],0
		mov rett,ecx
	.else
		mov rett,-1;word doesnt exist
	.endif
	.else
		mov rett,-1;one or more string parameters are null
	.endif
	popad
	mov eax,rett
	ret
	skipBrk:
	.while bl==brk && bl!=0
		inc esi
		mov bl,[esi]
	.endw
	db 0c3h
GetWord endp
IRCPrivMsg PROC lpszTarget:DWORD, lpszMessage:DWORD ;Send a message in IRC to a given channel
LOCAL	szBuffer[2025]:BYTE
	Invoke	lstrlen, lpszMessage
	push	eax
	Invoke	lstrlen, lpszTarget
	mov	ecx, eax
	pop	eax
	add	eax, ecx
	add	eax, 0CH
	cmp	eax, 2024D ;Everything within buffer length?
	jge	@@eret ;Jump if this is false
	Invoke	wsprintf, addr szBuffer, offset szPrvMsg, lpszTarget, lpszMessage ;Fill out the message string
	Invoke	lstrlen, addr szBuffer
	Invoke	send, dwSocket, addr szBuffer, eax, 0 ;Send the message
	xor	eax, eax 
	ret
@@eret:	mov	eax, -1 ;Basic error checking
	ret
IRCPrivMsg endp

;parse irc stream
Parse PROC 
	Invoke GetWord, addr commandbuf,1,":", addr parsedbuf,2025 ;Split the IRC message
	Invoke StripLF,addr parsedbuf ;Strip off any line endings
	 
	  ;ignore server pingpongs
	Invoke lstrcmp,addr szServer,addr parsedbuf ;If this part of the message contains server name, it most likely is a ping or pong. Pings and pongs will be handled later
	.if eax == 0 ;Comparison true
		ret ;Exit function
	.endif
     
	Invoke lstrcmp,addr szAboutcmd,addr parsedbuf ;Compare if this part of message is !about
	.if eax == 0
		Invoke	IRCPrivMsg, addr g_CurrentChan, addr szAbout ;Send the about message using message function
		ret ;Exit function
     .endif
	Ret ;Exit (nothing found in function)
Parse endp

ThreadFunc PROC arg:DWORD
LOCAL	szBuffer[2025]:BYTE
LOCAL	szDisplay[2025]:BYTE
LOCAL   parsebuf:DWORD
@@:	Invoke	recv, dwSocket, addr szBuffer, 2024, NULL ;Get data from socket
	Invoke lstrcpy, addr commandbuf, addr szBuffer ;Copy socket data into ram to parse
	Invoke Parse ;Call parse command to test for custom functions
.IF g_locked == TRUE
		xor	eax, eax
		ret
	.ENDIF
	lea	edi, szBuffer
	.IF DWORD PTR [edi] == 'GNIP';Was packet a PING?
		mov	DWORD PTR [edi], 'GNOP' 
		Invoke	lstrlen, addr szBuffer
		Invoke	send, dwSocket, addr szBuffer, eax, NULL ;Reply PONG
		jmp	@B
	.ENDIF
	inc	edi
	mov	AL, ':'
@@is:	inc	edi
	.IF AL == BYTE PTR [edi]
		jmp	@@ss
	.ELSEIF BYTE PTR [edi] == NULL
		jmp	@B
	.ELSE
		jmp	@@is
	.ENDIF
@@ss:	inc	edi
	mov	eax, DWORD PTR [edi]
	lea	ESI, szBuffer
	.IF DWORD PTR [ESI] == 'GNIP' ;Ping pong again
		mov	DWORD PTR [ESI], 'GNOP'
		Invoke	lstrlen, addr szBuffer
		Invoke	send, dwSocket, addr szBuffer, eax, NULL
	.ENDIF
	@@nxt:	lea	edi, szBuffer ;Break apart the buffer
		mov	ecx, 2025
		@@cls:	mov	BYTE PTR [edi], 0
			dec	ecx
			inc	edi
			cmp	ecx, 0
		jne	@@cls
		jmp	@B
	
ThreadFunc endp
Startup PROC
LOCAL	tid:DWORD ;Setup a variable for the parse thread
	Invoke	InitSocket ;Call to setup socket
	Invoke	ConnectTo, addr szServer, offset Port ;Connect to the assigned server
	Invoke	IRCLogin ;Login 
	Invoke	IRCJoin, addr szChannel ;Join
	Invoke	lstrcpy, addr g_CurrentChan, addr szChannel ;Cache the Channel
	mov	g_locked, FALSE ;Thread is not active
	Invoke	CreateThread, NULL, NULL, offset ThreadFunc, NULL, NULL, addr tid ;Create background thread so IRC commands can be easily parsed
	mov	g_hThread, eax ;Set thread Active
	xor	eax, eax
	Ret
Startup endp
Project PROC
		
      Invoke Startup ;Start up the IRC Connection
      SleepLoop:;Dirty way to keep background process open
	  Invoke Sleep,10000
	 jmp SleepLoop
Project endp
end Project