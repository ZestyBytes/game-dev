extends AudioStreamPlayer
class_name Sound

## Procedural sound effects - no audio assets needed, matches the original
## web version's approach (which synthesized tones with the Web Audio API
## instead of shipping sample files).

const SAMPLE_RATE := 44100.0

func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	gen.buffer_length = 0.3
	stream = gen
	play()
	# Silence isn't emitted until the buffer is fed, so this idles at 0
	# volume/energy until a tone is queued below.

func _playback() -> AudioStreamGeneratorPlayback:
	return get_stream_playback()

func _tone(freq: float, duration: float, gain: float = 0.2) -> void:
	var pb := _playback()
	if pb == null:
		return
	var frames := int(SAMPLE_RATE * duration)
	var phase := 0.0
	var step := freq / SAMPLE_RATE
	for i in range(frames):
		# Simple decay envelope so tones don't click at the tail.
		var envelope: float = 1.0 - (float(i) / frames)
		var sample: float = sin(phase * TAU) * gain * envelope
		phase = fmod(phase + step, 1.0)
		if pb.get_frames_available() > 0:
			pb.push_frame(Vector2(sample, sample))

## A short rising tone for a match; pitch climbs with combo depth, mirroring
## the web version's per-chain-depth tone.
func play_match(combo_depth: int) -> void:
	var freq: float = 440.0 + min(combo_depth, 6) * 90.0
	_tone(freq, 0.09, 0.18)

## A low "can't do that" thud for an invalid swap.
func play_bonk() -> void:
	_tone(140.0, 0.08, 0.15)

func play_round_end(won: bool) -> void:
	if won:
		_tone(660.0, 0.25, 0.2)
	else:
		_tone(220.0, 0.3, 0.2)
