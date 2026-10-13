extends SceneTree
func _initialize() -> void:
	var found := DiskLocator.find()
	var level := 2
	var col := 340
	var ticks := 1500
	var chase := false
	var dump_a := 0
	var dump_n := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="): level = int(a.substr(8))
		elif a.begins_with("--col="): col = int(a.substr(6))
		elif a.begins_with("--ticks="): ticks = int(a.substr(8))
		elif a == "--chase": chase = true
		elif a.begins_with("--dump="):
			var parts := a.substr(7).split(",")
			dump_a = parts[0].hex_to_int()
			dump_n = int(parts[1])
	var g := Game.new()
	g.setup(found["disks"], level)
	root.add_child(g)
	await process_frame
	await process_frame
	g.jump_to_col(col)
	Input.action_press("fire")
	for t in ticks:
		g._invuln = 100
		g.py = 20 + (t / 40) % 180
		if chase:
			var best: Enemy = null
			for e in g._enemies:
				if e.vm_slot >= 0 and e.x < 330 and e.y < 230 and (e.hp > 0 or e.vm_draws.size() > 0) and (best == null or e.vm_draws.size() > best.vm_draws.size() or e.hp > best.hp):
					best = e
			if best != null:
				var ty := int(best.y) + best.hit_h / 2 - 4
				g.py = clampi(ty - 8 + (t / 5) % 21, 3, 212)
		g._physics_process(0.02)
		if t % 100 == 0 or t == ticks - 1:
			print("   scene ptrs %X %X hit calls %d hits %d" % [g._vm.cpu.r32(int(g._vm.syms.get("scene_a", 0))), g._vm.cpu.r32(int(g._vm.syms.get("scene_b", 0))), g._vm.dbg_hit_calls, g._vm.dbg_hits])
			var sl := ""
			for sh in g._weapons.shots:
				sl += " (%d,%d)" % [sh.x, sh.y]
			print("   box %s shots %s py %d" % [str(g._vm.dbg_box), sl, g.py])
			if dump_n > 0:
				var line := "   mem %X:" % dump_a
				for i in dump_n:
					line += " %04X" % g._vm.cpu.r16(dump_a + i * 2)
				print(line)
			print("t=%d scroll %.0f locked %s enemies %d" % [t, g.scroll, str(g.scroll_locked), g._enemies.size()])
			for e in g._enemies:
				if e.vm_slot >= 0:
					print("   h=%04X type %d fl %02X x %d y %d hp %d fr %d hit %dx%d inv %s flashbit %s 19=%02X 14=%02X draws %d blits %d parts %d px %d py %d" % [e.rw(0x1C), e.type, e.flags, e.x, e.y, e.hp, e.frame, e.hit_w, e.hit_h, str(e.invulnerable), str(e.flash_bit), e.rb(0x19), e.rb(0x14), e.vm_draws.size(), e.vm_blits.size(), e.parts.size(), g.px, g.py])
					if t >= ticks - 100:
						for d in e.vm_draws: print("      draw ", d)
						for b in e.vm_blits: print("      blit con0=%04X a=%05X b=%05X dst=%04X h=%d w=%d" % [b["con0"], b["a"], b["b"], b["dst_off"], b["h"], b["w"]])
	print("finished: %s score %d" % [str(g._finished), g.get_score()])
	quit(0)
