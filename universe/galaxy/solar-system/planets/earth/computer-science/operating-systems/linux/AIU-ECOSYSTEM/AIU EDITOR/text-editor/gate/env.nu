
export const gate_dir = path self | path dirname

export const project_root = $gate_dir | path dirname

export const package_dir = $project_root | path join "editor"

export const package_src = $package_dir

export const tools_dir = $project_root | path join "tools"

export def home_dir [] {
    $env.HOME
}

export def racket_bin [] {
    home_dir | path join "opt" | path join "racket-full" | path join "bin" | path join "racket"
}

export def rkt_files [] {
    glob $"($package_src)/**/*.rkt" | lines
}
