extends Control

const INSTRUCTIONS_PER_FRAME := 11 ## This is about 660 instructions per sec if fps is 60hz
const ROM_PATH := "2-ibm-logo.ch8"
const FONT_START := 0x50
const FONT := [
	0xF0, 0x90, 0x90, 0x90, 0xF0, ## 0
	0x20, 0x60, 0x20, 0x20, 0x70, ## 1
	0xF0, 0x10, 0xF0, 0x80, 0xF0, ## 2
	0xF0, 0x10, 0xF0, 0x10, 0xF0, ## 3
	0x90, 0x90, 0xF0, 0x10, 0x10, ## 4
	0xF0, 0x80, 0xF0, 0x10, 0xF0, ## 5
	0xF0, 0x80, 0xF0, 0x90, 0xF0, ## 6
	0xF0, 0x10, 0x20, 0x40, 0x40, ## 7
	0xF0, 0x10, 0x20, 0x40, 0x40, ## 8
	0xF0, 0x90, 0xF0, 0x10, 0xF0, ## 9
	0xF0, 0x90, 0xF0, 0x90, 0x90, ## A
	0xE0, 0x90, 0xE0, 0x90, 0xE0, ## B
	0xF0, 0x80, 0x80, 0x80, 0xF0, ## C
	0xE0, 0x90, 0x90, 0x90, 0xE0, ## D
	0xF0, 0x80, 0xF0, 0x80, 0xF0, ## E
	0xF0, 0x80, 0xF0, 0x80, 0x80, ## F
]

var stack: Array[int] = []
var delay_timer := 0
var sound_timer := 0
var rom_loaded := false

var img: Image
var tex: ImageTexture
@onready var screen: TextureRect = $Screen

var display := PackedByteArray()

var memory := PackedByteArray()
var V := PackedByteArray()  ## Registers from VO to VF
var I := 0 ## This is the index register
var pc := 0x200 ## pc stands for program counter, if you arent in the know. 

func load_rom(path: String) -> bool:
	memory.resize(4096) ## Resets everything to a clean slate
	memory.fill(0)
	V.resize(16)
	V.fill(0)
	display.resize(64 * 32)
	display.fill(0)
	stack.clear()
	I = 0
	pc = 0x200
	delay_timer = 0
	sound_timer = 0
	
	for i in FONT.size():  ## Font gets loaded into the reserved area
		memory[FONT_START + i] = FONT[i]
	
	var rom := FileAccess.get_file_as_bytes(path)
	
	if rom.is_empty():
		push_error("Could not load ROM: " + path)
		return false
	
	if rom.size() > memory.size() - 0x200:
		push_error("ROM is too large to fit in CHIP-8 memory: " + path)
		return false
	
	for i in rom.size():
		memory[0x200 + i] = rom[i]
	
	print("Loaded ", rom.size(), " bytes from ", path)
	return true

func setup_screen() -> void:
	img = Image.create_empty(64, 32, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	tex = ImageTexture.create_from_image(img)
	screen.texture = tex

func draw_screen() -> void:
	for sy in 32:
		for sx in 64:
			var on := display[sy * 64 + sx] == 1
			img.set_pixel(sx, sy, Color.WHITE if on else Color.BLACK)
	tex.update(img)

func _ready() -> void:
	setup_screen()
	rom_loaded = load_rom(ROM_PATH)

func _physics_process(_delta: float) -> void:
	if not rom_loaded:
		return
	
	for i in INSTRUCTIONS_PER_FRAME:
		step()
	
	draw_screen()

func step() -> void:
	if not rom_loaded:
		return
	
	if pc < 0 or pc + 1 >= memory.size():
		push_error("Program counter outside memory: 0x%03X" % pc)
		rom_loaded = false
		return
		
	var opcode := (memory[pc] << 8) | memory[pc + 1]
	pc += 2
	
	var first := (opcode & 0xF000) >> 12
	var x := (opcode & 0x0F00) >> 8 
	var y := (opcode & 0x00F0) >> 4
	var n := opcode & 0x000F
	var nn := opcode & 0x00FF
	var nnn := opcode & 0x0FFF
	
	match first:
		0x0:
			if opcode == 0x00E0:
				display.fill(0)
			elif opcode == 0x00EE:
				pc = stack.pop_back()
		0x1:
			pc = nnn
		0x2:
			stack.append(pc)
			pc = nnn
		0x3:
			if V[x] == nn:
				pc += 2
		0x4:
			if V[x] != nn:
				pc += 2
		0x5:
			if V[x] == V[y]:
				pc += 2
		0x6:
			V[x] = nn 
		0x7:
			V[x] = (V[x] + nn) & 0xFF
		0x8:
			match n:
				0x0:
					V[x] = V[y]
				0x1:
					V[x] = V[x] | V[y]
				0x2:
					V[x] = V[x] & V[y]
				0x3:
					V[x] = V[x] ^ V[y]
				0x4:
					var sum := V[x] + V[y]
					var flag := 1 if sum > 255 else 0
					V[x] = sum & 0xFF
					V[0xF] = flag
				0x5:
					var diff := V[x] - V[y]
					var flag := 1 if V[x] >= V[y] else 0
					V[x] = diff & 0xFF
					V[0xF] = flag
				0x7:
					var diff := V[y] - V[x]
					var flag := 1 if V[y] >- V[x] else 0 
					V[x] = diff & 0xFF
					V[0xF] = flag
				0x6:
					var flag := V[y] & 1
					V[x] = (V[y] >> 1) & 0xFF
					V[0xF] = flag
				0xE:
					var flag := V[y] & 1
					V[x] = (V[y] << 1) & 0xFF
					V[0xF] = flag
				0xB:
					pc = nnn + V[0]
				0xC:
					V[x] = randi_range(0, 255) & nn
				_:
					print("UNKNOWN %04X" % opcode)
		0x9:
			if V[x] != V[y]:
				pc += 2
		0xA:
			I = nnn
		0xF:
			match nn:
				0x1E:
					I = (I + V[x]) & 0xFFFF
				0x29:
					I = FONT_START + (V[x] & 0xF) * 5
				0x33:
					memory[I] = V[x] / 100
					memory[I + 1] = (V[x] / 10) % 10
					memory[I + 2] = V[x] % 10
				0x55: ## Stores V0 through Vx in memory
					for i in range(x + 1):
						memory[I] = V[i]
						I += 1
				0x65: ## Loads V0 through Vx from memory
					for i in range(x + 1):
						V[i] = memory[I]
						I += 1
		0xD:
			var px := V[x] % 64
			var py := V[y] % 32
			V[0xF] = 0
			for row in n:
				var sprite_byte := memory[I + row]
				for col in 8:
					var bit := (sprite_byte >> (7 - col)) & 1
					if bit == 0:
						continue
					var sx := px + col
					var sy := py + row
					if sx >= 64 or sy >= 32:
						continue
					var idx = sy * 64 + sx
					if display[idx] == 1:
						V[0xF] = 1
					display[idx] = display[idx] ^ 1
		_:
			print("UNKNOWN %04X" % opcode)
