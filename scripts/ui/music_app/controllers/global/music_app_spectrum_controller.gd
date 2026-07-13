class_name MusicAppSpectrumController
extends RefCounted

signal spectrum_changed(bass: float, mid: float, treble: float, volume: float)
signal detailed_spectrum_changed(
	kick: float,
	bass: float,
	vocal: float,
	instrument_mid: float,
	treble: float,
	treble_air: float,
	rms: float,
	energy_onset: float
)
signal beat_detected(strength: float)

const ANALYZER_BUS_NAME := "Master"
const KICK_RANGE := Vector2(35.0, 95.0)
const BASS_RANGE := Vector2(20.0, 150.0)
const MID_RANGE := Vector2(150.0, 2400.0)
const VOCAL_RANGE := Vector2(280.0, 2400.0)
const INSTRUMENT_MID_RANGE := Vector2(700.0, 4200.0)
const TREBLE_RANGE := Vector2(2400.0, 12000.0)
const TREBLE_AIR_RANGE := Vector2(8000.0, 16000.0)
const SPECTRUM_SCALE := 42.0
const SMOOTH_SPEED := 10.0
const DETAILED_SMOOTH_SPEED := 12.0
const RELEASE_SPEED := 5.0
const BEAT_BASELINE_SPEED := 1.8
const BEAT_THRESHOLD := 0.20
const BEAT_MIN_BASS := 0.18
const BEAT_COOLDOWN_SECONDS := 0.16
const ONSET_BASELINE_SPEED := 2.2

var kick := 0.0
var bass := 0.0
var mid := 0.0
var vocal := 0.0
var instrument_mid := 0.0
var treble := 0.0
var treble_air := 0.0
var volume := 0.0
var rms := 0.0
var energy_onset := 0.0
var beat_strength := 0.0

var _analyzer_instance
var _beat_baseline := 0.0
var _energy_baseline := 0.0
var _beat_cooldown := 0.0
var _missing_analyzer_warned := false

func _init() -> void:
	_resolve_analyzer_instance()

func process(delta: float) -> void:
	if _analyzer_instance == null:
		_resolve_analyzer_instance()
	if _analyzer_instance == null:
		_decay(delta)
		spectrum_changed.emit(bass, mid, treble, volume)
		_emit_detailed_spectrum()
		return

	var next_kick := _read_frequency_range(KICK_RANGE)
	var next_bass := _read_frequency_range(BASS_RANGE)
	var next_mid := _read_frequency_range(MID_RANGE)
	var next_vocal := _read_frequency_range(VOCAL_RANGE)
	var next_instrument_mid := _read_frequency_range(INSTRUMENT_MID_RANGE)
	var next_treble := _read_frequency_range(TREBLE_RANGE)
	var next_treble_air := _read_frequency_range(TREBLE_AIR_RANGE)
	var smooth_alpha := clampf(1.0 - exp(-SMOOTH_SPEED * delta), 0.0, 1.0)
	var detailed_alpha := clampf(1.0 - exp(-DETAILED_SMOOTH_SPEED * delta), 0.0, 1.0)

	kick = lerpf(kick, next_kick, detailed_alpha)
	bass = lerpf(bass, next_bass, smooth_alpha)
	mid = lerpf(mid, next_mid, smooth_alpha)
	vocal = lerpf(vocal, next_vocal, detailed_alpha)
	instrument_mid = lerpf(instrument_mid, next_instrument_mid, detailed_alpha)
	treble = lerpf(treble, next_treble, smooth_alpha)
	treble_air = lerpf(treble_air, next_treble_air, detailed_alpha)
	rms = clampf((kick * 0.24) + (bass * 0.28) + (vocal * 0.20) + (instrument_mid * 0.16) + (treble_air * 0.12), 0.0, 1.0)
	volume = clampf((bass * 0.50) + (mid * 0.32) + (treble * 0.18), 0.0, 1.0)
	_update_energy_onset(delta)

	_update_beat(delta)
	spectrum_changed.emit(bass, mid, treble, volume)
	_emit_detailed_spectrum()

func _resolve_analyzer_instance() -> void:
	var bus_index := AudioServer.get_bus_index(ANALYZER_BUS_NAME)
	if bus_index < 0:
		return

	for effect_index in AudioServer.get_bus_effect_count(bus_index):
		var effect := AudioServer.get_bus_effect(bus_index, effect_index)
		if effect is AudioEffectSpectrumAnalyzer:
			_analyzer_instance = AudioServer.get_bus_effect_instance(bus_index, effect_index)
			_missing_analyzer_warned = false
			return

	if not _missing_analyzer_warned:
		push_warning("Music spectrum analyzer is missing from the Master audio bus.")
		_missing_analyzer_warned = true

func _read_frequency_range(frequency_range: Vector2) -> float:
	var magnitude: Vector2 = _analyzer_instance.get_magnitude_for_frequency_range(
		frequency_range.x,
		frequency_range.y,
		AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE
	)
	return clampf((magnitude.x + magnitude.y) * SPECTRUM_SCALE, 0.0, 1.0)

func _update_beat(delta: float) -> void:
	_beat_cooldown = maxf(0.0, _beat_cooldown - delta)
	var baseline_alpha := clampf(1.0 - exp(-BEAT_BASELINE_SPEED * delta), 0.0, 1.0)
	_beat_baseline = lerpf(_beat_baseline, kick, baseline_alpha)

	beat_strength = clampf(kick - _beat_baseline, 0.0, 1.0)
	if _beat_cooldown > 0.0:
		return
	if kick < BEAT_MIN_BASS or beat_strength < BEAT_THRESHOLD:
		return

	_beat_cooldown = BEAT_COOLDOWN_SECONDS
	beat_detected.emit(beat_strength)

func _update_energy_onset(delta: float) -> void:
	var baseline_alpha := clampf(1.0 - exp(-ONSET_BASELINE_SPEED * delta), 0.0, 1.0)
	_energy_baseline = lerpf(_energy_baseline, rms, baseline_alpha)
	energy_onset = clampf((rms - _energy_baseline) * 1.8, 0.0, 1.0)

func _emit_detailed_spectrum() -> void:
	detailed_spectrum_changed.emit(
		kick,
		bass,
		vocal,
		instrument_mid,
		treble,
		treble_air,
		rms,
		energy_onset
	)

func _decay(delta: float) -> void:
	var release_alpha := clampf(1.0 - exp(-RELEASE_SPEED * delta), 0.0, 1.0)
	kick = lerpf(kick, 0.0, release_alpha)
	bass = lerpf(bass, 0.0, release_alpha)
	mid = lerpf(mid, 0.0, release_alpha)
	vocal = lerpf(vocal, 0.0, release_alpha)
	instrument_mid = lerpf(instrument_mid, 0.0, release_alpha)
	treble = lerpf(treble, 0.0, release_alpha)
	treble_air = lerpf(treble_air, 0.0, release_alpha)
	volume = lerpf(volume, 0.0, release_alpha)
	rms = lerpf(rms, 0.0, release_alpha)
	energy_onset = lerpf(energy_onset, 0.0, release_alpha)
	beat_strength = 0.0
