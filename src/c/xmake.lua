
target("tm42_math_test")
	set_languages("clatest")
	set_kind("binary")
	add_files("tests/tm42_math_test.c")
	add_includedirs(".")
	add_links("m")

target("tm42_camera_test")
	set_languages("clatest")
	set_kind("binary")
	add_files("tests/tm42_camera_test.c")
	add_includedirs(".")
	add_links("m")