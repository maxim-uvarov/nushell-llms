use openai.nu ask

export def main [
    prompt?: string
    --path: path = '/Users/user/temp/llms/'
    --codium # copy result to buffer and output into codium --diff
] {
    let prompt = if $prompt == null { } else { $prompt }

    let answer = "**Prompt:**
         Carefully review the following text for grammar, spelling, punctuation, clarity, and style.

        Edit it by using **Critic Markup** to highlight changes:

        * Substitutions: {~~ original text ~> corrected text ~~}
        * Additions: {++ inserted text ++}
        * Deletions: {-- deleted text --}
        * Comments (optional if needed): {>> comment <<}

        **Important instructions:**
        * Do not mark capitalization changes
        * If you added comma or other punctuation without changing words - provide those changes in separate tags
        * Only output the edited version with Critic Markup annotations.
        * Do not provide explanations or additional commentary.
        * Preserve the original meaning and tone unless correction requires slight adjustments.
    "
    | str replace -arm '^\s+' ''
    | ask $prompt --system $in --no-stream

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
