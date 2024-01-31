export def main [prompt] {
    correct_english $prompt
}


export def correct_english [
    prompt: string
] {
    let $prompt_with_tick = $prompt | str replace -a '●' '`'
    let $answer = (
        llm prompt --no-stream -s "Edit the message and correct grammar. Provide only edited message. Don't change markdown markup." $prompt_with_tick
    )

    let filename = (now-fn)

    $prompt_with_tick | save $'/Users/user/Documents/local_files/llms/prompt(now-fn).txt'
    $answer | save $'/Users/user/Documents/local_files/llms/answer(now-fn).txt'

    $answer | pbcopy

    codium --diff $'/Users/user/Documents/local_files/llms/prompt($filename).txt' $'/Users/user/Documents/local_files/llms/answer($filename).txt'
}

def 'now-fn' [
    --pretty (-P)
] {
    if $pretty {
        date now | format date '%Y-%m-%d-%H:%M:%S'
    } else {
        date now | format date '%Y%m%d-%H%M%S'
    }
}
