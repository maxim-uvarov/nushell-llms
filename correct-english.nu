use openai.nu ask

export def main [
    prompt?: string
    --path: path = '/Users/user/temp/llms/'
    --codium # copy result to buffer and output into codium --diff
] {
    let prompt = if $prompt == null { } else { $prompt }

    let answer = "Carefully review the following text for grammar, spelling, punctuation, clarity, and style.
    Edit the text using Critic Markup with the following conventions:
    - Substitutions: {~~ original text ~> corrected text ~~}
    - Additions: {++ inserted text ++}
    - Deletions: {-- deleted text --}
    - Comments (optional, if necessary): {>> comment <<}

    Important Rules:
    - Ignore capitalization-only changes (do not mark case edits).
    - Punctuation-only edits (e.g., adding commas, periods) must each be enclosed in a separate Critic Markup tag.
    - Preserve the original meaning and tone unless a change is necessary for clarity or readability.
    - Only output the edited text with Critic Markup annotations.Do not include explanations, summaries, or any extra commentary.
    - Follow these rules precisely.
    "
    | str replace -arm '^\s+' ''
    | ask $prompt --system $in --no-stream --temperature 0.3

    let filename = now-fn

    let prompt_path = $path | path join $'prompt($filename).txt'
    let answer_path = $path | path join $'answer($filename).txt'

    $prompt | save -f $prompt_path
    $answer | save -f $answer_path

    if $codium {
        $answer | pbcopy

        codium -n --diff $prompt_path $answer_path
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
