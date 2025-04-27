use openai.nu ask

export def main [
    prompt?: string
    --path: path = '/Users/user/temp/llms/'
    --codium # copy result to buffer and output into codium --diff
] {
    let prompt = if $prompt == null { } else { $prompt }

    let answer = '
        Edit the message and correct grammar.
        Provide only the edited message. Do not change markdown markup.'
    | str replace -arm '^\s+' ''
    | ask $prompt --system $in --no-stream

    let filename = now-fn

    let prompt_path = $path | path join $'($filename)_a_prompt.txt'
    let answer_path = $path | path join $'($filename)_b_answer.txt'
    let diff_path = $path | path join $'($filename)_c_diff.txt'

    $prompt | save -f $prompt_path
    $answer | save -f $answer_path

    if $codium {
        $answer | pbcopy

        git diff --word-diff --word-diff-regex=. -U10000 $prompt_path $answer_path
        | lines
        | where $it !~ '^(diff --git|---|index|\+\+\+|@@) '
        | to text
        | save $diff_path -f

        zellij action new-tab -n worddiff --cwd /Users/user/temp/llms --layout classic
        zellij edit --floating --width 90% --height 90% -x 5% -y 5% $diff_path
        ^open /Users/user/Applications/WezTerm.app
    } else {
        $answer
    }
}

def 'now-fn' [
    --pretty (-P)
] {
    date now
    | format date (if $pretty { '%Y-%m-%d-%H:%M:%S' } else { '%Y%m%d-%H%M%S' })
}
