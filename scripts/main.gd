extends Control

const INSTRUCTIONS_PER_FRAME := 11 ## This is about 660 instructions per sec if fps is 60hz

var img: Image
var tex: ImageTexture
@onready var screen: TextureRect = $Screen

var display := PackedByteArray()

var memory := PackedByteArray()
var V := PackedByteArray()  ## Registers from VO to VF
var I := 0 ## This is the index register
var pc := 0x200 ## pc stands for program counter, if you arent in the know. 

func setup_screen() -> void:
	img = Image.create_empty(64, 32, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	tex = ImageTexture.create_from_image(img)
	screen.texture = tex

func draw_screen() -> void:
	for sy in 32:
		tex.update(img)
		for sx in 64:
			var on := display[sy * 64 + sx] == 1
			img.set_pixel(sx, sy, Color.WHITE if on else Color.BLACK)

func _ready() -> void:
	setup_screen()
	display.resize(64 * 32)
	var rom: PackedByteArray = FileAccess.get_file_as_bytes("res://roms/2-ibm-logo.ch8")
	memory.resize(4096)
	V.resize(16)
	for i in rom.size():
		memory[0x200 + i] = rom[i]

func _physics_process(_delta: float) -> void:
	for i in INSTRUCTIONS_PER_FRAME:
		step()
	draw_screen()

func step() -> void:
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
			display.fill(0)
		0x1:
			pc = nnn
		0x6:
			V[x] = nn 
		0x7:
			V[x] = (V[x] + nn) & 0xFF
		0xA:
			I = nnn
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
