extends Control

var memory := PackedByteArray()
var V := PackedByteArray()  ## Registers from VO to VF
var I := 0 ## This is the index register
var pc := 0x200 ## pc stands for program counter, if you arent in the know. 

func _ready() -> void:
	var rom: PackedByteArray = FileAccess.get_file_as_bytes("res://roms/2-ibm-logo.ch8")
	memory.resize(4096)
	V.resize(16)
	for i in rom.size():
		memory[0x200 + i] = rom[i]
	print("mem 200 = %02X" % memory[0x200])
	print("mem 201 = %02X" % memory [0x201])
	print("rom size = ", rom.size())
	for n in 20:
		step()

func step() -> void:
	var opcode := (memory[pc] << 8) | memory[pc + 1]
	pc += 2
	print("%04X" % opcode)
