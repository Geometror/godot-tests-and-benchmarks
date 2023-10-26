extends Node3D

@export var print_measurements : bool = true
@export var warmup_in_seconds = 3
@export var time_per_bechmark_in_seconds = 10
@export var particle_process_material : ParticleProcessMaterial
@export var cpu_particles_node : CPUParticles3D
@export var particle_mesh : Mesh
@export var benchmark_sets : Array[BenchmarkParams]

@onready var particle_container = $particle_container
@onready var timer = $timer

var mspf_sum = 0
var mspf_probe_count = 0
var current_benchmark = ""

var benchmark_results: Array[String] = []

func _ready():
	timer.connect("timeout", measure_mspf)

	print("Starting benchmarks.")

	# Execute benchmarks
	for benchmark_set : BenchmarkParams in benchmark_sets:
		benchmark_results.append(
			"🟩 Results (particle systems: %s, particles per system: %s):" % 
			[benchmark_set.particle_systems, benchmark_set.particle_amount_per_system])
		
		await benchmark(bench_cpu_particles.bind(benchmark_set.particle_systems, benchmark_set.particle_amount_per_system))
		await benchmark(bench_gpu_particles.bind(benchmark_set.particle_systems, benchmark_set.particle_amount_per_system, 1))
		await benchmark(bench_gpu_particles.bind(benchmark_set.particle_systems, benchmark_set.particle_amount_per_system, 10))
		await benchmark(bench_gpu_particles.bind(benchmark_set.particle_systems, benchmark_set.particle_amount_per_system, benchmark_set.particle_systems))
		
		benchmark_results.append("")
	print_results()
	
	# Necessary since there is no way to manually flush the print buffer
	await get_tree().create_timer(0.5)
	get_tree().quit()

func print_results():
	print("-------------------------------------------------------------")
	for result in benchmark_results:
		print(result)
	print("-------------------------------------------------------------")

# Benchmarking helpers

func benchmark(benchmark_callback: Callable):
	print("Warmup (%s seconds)" % warmup_in_seconds)
	await get_tree().create_timer(warmup_in_seconds).timeout
	benchmark_callback.call()
	await get_tree().create_timer(time_per_bechmark_in_seconds).timeout
	end_mspf_measurement()
	clear_particle_container()

func start_mspf_measurement(benchmark_name: String):
	print("Starting benchmark: " + benchmark_name)
	current_benchmark = benchmark_name
	timer.start()

func end_mspf_measurement():
	if current_benchmark == "":
		return
	
	print("Benchmark " + current_benchmark + " finished")
	var avg_mspf = mspf_sum as float / mspf_probe_count
	print("Average mspf: %s " % avg_mspf)
	benchmark_results.append("%s : %.4f mspf" % [current_benchmark, avg_mspf])

	timer.stop()
	mspf_sum = 0
	mspf_probe_count = 0
	current_benchmark = ""

func measure_mspf():
	var current_mspf = 1000/Engine.get_frames_per_second()
	mspf_sum += current_mspf
	mspf_probe_count += 1

	var avg_mspf = mspf_sum as float / mspf_probe_count
	if print_measurements:
		print("mspf > AVG: %.4f mspf, CURRENT: %.4f mspf" % [avg_mspf, current_mspf])

func clear_particle_container():
	for child in particle_container.get_children():
		child.free()

# Benchmarks

func bench_cpu_particles(particle_systems: int, particle_amount_per_system: int):
	for i in range(particle_systems):
		var particles : CPUParticles3D = cpu_particles_node.duplicate()
		particles.visible = true
		particles.amount = particle_amount_per_system
		particles.name = "cpu_particle_sys_" + str(i)
		particle_container.add_child(particles)
	
	start_mspf_measurement("CPU Particles")

func bench_gpu_particles(particle_systems: int, particle_amount_per_system: int, unique_particle_materials: int):
	var process_materials : Array[ParticleProcessMaterial] = []

	# Create particle materials
	for i in range(unique_particle_materials):
		process_materials.append(particle_process_material.duplicate(true))

	for i in range(particle_systems):
		var particles = GPUParticles3D.new()
		particles.amount = particle_amount_per_system
		particles.emitting = true
		particles.lifetime = 1
		particles.process_material = process_materials[i % unique_particle_materials]

		particles.draw_pass_1 = particle_mesh

		particles.name = "gpu_particle_sys_" + str(i)
		particle_container.add_child(particles)

	start_mspf_measurement("GPU Particles (unique process materials %s)" % unique_particle_materials)

