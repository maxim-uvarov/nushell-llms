#!/usr/bin/env nu

# MIT LICENCE
#
# Copyright 2023 Gabin Lefranc, Maxim Uvarov
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

use utils.nu

def get-api [] {
    '/Users/user/git/nushell-openai/git-ignored-file'
    | if ($in | path exists) {
        open | decode base32hex | decode | str substring 1..
        | return $in
    }

    if not ("OPENAI_API_KEY" in $env) {
        error make {msg: "OPENAI_API_KEY not set"}
        exit 1
    }
    return $env.OPENAI_API_KEY
}
# Lists the OpenAI models
export def models [
    --model: string = '' # The model to retrieve
] {
    let suffix = if $model != "" { $"/($model)" }

    http get $"https://api.openai.com/v1/models($suffix)" -H ["Authorization" $"Bearer (get-api)"]
}

export-env {
    $env.OPENAI_DATA = {}
}

export def --env "set previous_messages" [messages: list] {
    $env.OPENAI_DATA = {
        previous_messages: $messages
    }
}
def --env "get previous_messages" [] {
    if ($env | get -i OPENAI_DATA) != null {
        if ($env.OPENAI_DATA | get -i previous_messages) != null {
            $env.OPENAI_DATA.previous_messages
        } else {
            []
        }
    } else {
        []
    }
}

# Helper function to add a parameter to a record if it's not null.
def add_param [name: string, value: any] {
    if $value != null {
        upsert $name $value
    } else { }
}
# Chat completion API call.
export def "api chat-completion" [
    model: string # ID of the model to use.
    messages: list # List of messages to complete from.
    --max-tokens: int # The maximum number of tokens to generate in the completion.
    --temperature: number # The temperature used to control the randomness of the completion.
    --top-p: number # The top-p used to control the randomness of the completion.
    --n: int # How many completions to generate for each prompt. Use carefully, as it's a token eater.
    --stop: string # Up to 4 sequences where the API will stop generating further tokens.
    --frequency-penalty: number # A penalty to apply to each token that appears more than once in the completion.
    --presence-penalty: number # A penalty to apply if the specified tokens don't appear in the completion.
    --logit-bias: record # A record to modify the likelihood of specified tokens appearing in the completion
    --user: string # A unique identifier representing your end-user.
    --no-stream
] {
    # See https://platform.openai.com/docs/api-reference/chat/create
    let params = {model: $model messages: $messages}
    | add_param "max_tokens" $max_tokens
    | add_param "temperature" $temperature
    | add_param "top_p" $top_p
    | add_param "n" $n
    | add_param "stop" $stop
    | add_param "frequency_penalty" $frequency_penalty
    | add_param "presence_penalty" $presence_penalty
    | add_param "logit_bias" $logit_bias
    | add_param "user" $user
    | add_param "stream" true

    let streaming = not ($no_stream or ($nu.is-interactive == false))

    if $streaming {
        clear --keep-scrollback
        utils print-current-commandline
        print -n (ansi --escape "s")
    }

    (
        http post "https://api.openai.com/v1/chat/completions"
        -H ["Authorization" $"Bearer (get-api)"]
        -t 'application/json'
        $params
    )
    | lines
    | each {|line|
        if $line == "data: [DONE]" {
            if $streaming {
                print -n $'(ansi --escape "u")(ansi --escape "J")'
            }
            return
        }

        $line
        | if ($in in ["\n" '']) { } else {
            str substring 6..
            | from json
            | get choices.0.delta
            | if ($in | is-not-empty) { $in.content }
        }
        | if $streaming {
            tee { $'(ansi yellow)($in)(ansi reset)' | print -n }
        } else { }
    }
    | str join
    | wrap response
}

# Ask for a command to run. Will return one line command.
export def --env command [
    input?: string # The command to run. If not provided, will use the input from the pipeline
    --max-tokens: int # The maximum number of tokens to generate, defaults to 64
    --no-interactive # If true, will not ask to execute and will pipe the result
] {
    let input = ($in | default $input)
    if $input == null {
        error make {msg: "input is required"}
    }
    let max_tokens = ($max_tokens | default 200)

    let messages = [
        {"role": "system" "content": "You are a command line analyzer. Write the command that best fits my request in a \"Command\" markdown chapter then describe each parameter used in a \"Explanation\" markdown chapter."}
        {"role": "user" "content": $input}
    ]
    let result = (api chat-completion "gpt-3.5-turbo" $messages --temperature 0 --top-p 1.0 --frequency-penalty 0.2 --presence-penalty 0 --max-tokens $max_tokens)
    # return $result
    set previous_messages ($messages | append [$result.choices.0.message])

    let result = $result.choices.0.message.content
    $result | utils display markdown

    if not $no_interactive {
        print ""
        if (input "Execute ? (y/n) ") == "y" {
            nu -c $"($result)"
        }
    }
}
# Continue a chat with GPT-3.5
export def --env chat [
    input?: string
    --reset # Reset the chat history
    --model: string = "gpt-3.5-turbo" # The model to use, defaults to gpt-3.5-turbo
    --max-tokens: int # The maximum number of tokens to generate, defaults to 150
] {
    let input = ($in | default $input)
    if $reset {
        set previous_messages []
        return
    }
    if $input == null {
        error make {msg: "input is required"}
    }

    let messages = (
        get previous_messages | append [
            {"role": "system" "content": "You are ChatGPT, a powerful conversational chatbot. Answer to me in informative way unless I tell you otherwise. You can format your message in markdown."}
            {"role": "user" "content": $input}
        ]
    )
    let result = (api chat-completion $model $messages --temperature 0 --top-p 1.0 --frequency-penalty 0.2 --presence-penalty 0 --max-tokens 300)
    # return $result
    set previous_messages ($messages | append [$result.choices.0.message])

    let result = $result.choices.0.message.content
    $result | utils display markdown
}

export def "git diff" [
    --max-tokens: int # The maximum number of tokens to generate, defaults to 100
    --no_interactive # If true, will not ask to commit and will pipe the result
] {
    let git_status = (^git status | str trim)
    if $git_status =~ "^fatal" {
        error make {msg: $git_status}
    }
    let result = (^git diff --cached --no-color --raw -p)
    if $result == "" {
        error make {msg: "No changes"}
    }
    # let result = ($result | lines | each {|line| $"    ($line)"} | str join "\n")
    let input = $"Get the git diff of the staged changes:
```sh
git diff --cached --no-color --raw -p
```

Result of the comand:
```diff($result)
```

Commit with a message that explains the staged changes:
```sh
git commit -m \""
    let max_tokens = ($max_tokens | default 2000)
    let openai_result = (api completion "gpt-3.5-turbo" --prompt $input --temperature 0.1 --top-p 1.0 --frequency-penalty 0 --presence-penalty 0 --max-tokens $max_tokens --stop '"')

    let openai_result = ($openai_result.choices.0.text | str trim)
    if not $no_interactive {
        print $"(ansi green)($openai_result)(ansi reset)"
        if (input "commit with this message ? (y/n) ") == "y" {
            git commit -m $openai_result
        }
    } else {
        $openai_result
    }
}

export def test [
    msg: string
] {

    api chat-completion "gpt-3.5-turbo" [{role: "user" content: "Hello!"}] --temperature 0 --top-p 1.0 --frequency-penalty 0.2 --presence-penalty 0 --max-tokens 64 --stop "\\n"
}

export def ask [
    ...input: string # The question to ask. If not provided, will use the input from the pipeline
    --model (-m): string = "gpt-4o-mini" # The model to use, defaults to gpt-3.5-turbo
    --max-tokens: int = 4000 # The maximum number of tokens to generate, defaults to 150
    --system: string = "Answer my question as if you were an expert in the field."
    --temperature: float = 0.7
    --top_p: float = 1.0
    --quiet (-q) # don't output the results
    --no-stream
] {
    let input = if $input == [] { } else { $input | str join "\n\n---\n\n" }
    let messages = [
        {"role": "system" "content": $system}
        {"role": "user" "content": $input}
    ]
    let result = (
        api chat-completion $model $messages
        --temperature $temperature --top-p $top_p
        --frequency-penalty 0
        --presence-penalty 0
        --max-tokens $max_tokens
        --no-stream=$no_stream
    )

    # $result.response | print

    let content = $result.response
    | lines
    | str trim
    | str join "\n"

    {
        system: $system
        user: $input
        max-tokens: $max_tokens
        model: $model
    }
    | append $result
    | to yaml
    | save -ar ~/full_log.yaml

    {
        input: $input
        system: $system
        temperature: $temperature
        top-p: $top_p
        content: $content
    }
    | [$in]
    | to yaml
    | save -ar ~/short_log.yaml

    if not $quiet { $content }
}

export def 'pu-add' [
    command: string
] {
    do { pueue add -p $'nu -c "source /Users/user/apps-files/github/nushell-openai/openai.nu; ($command)" --config "($nu.config-path)" --env-config "($nu.env-path)"' }
    | null
}

# Make multiple prompts with parameters defined in YAML file
export def 'multiple_prompts' [
    prompt: string
    --config_file_path: string = '~/.alfred_llms_config.yaml'
] {
    open $config_file_path
    | each {|i|
        $i
        | items {|k v| [$'--($k)' $v] }
        | flatten
        | pu-add $"results_record '($prompt)' ($in | str join ' ')"
    }
}

export def 'bard_prompt' [
    prompt: string
    --temperature = 1.0
    --candidate_count = 1
] {
    (
        http post $"https://generativelanguage.googleapis.com/v1beta2/models/text-bison-001:generateText?key=($env.PALM_API_KEY)"
        -t 'application/json' {
            "prompt": {
                "text": $prompt
            }
            "temperature": $temperature
            "candidate_count": $candidate_count
        }
    )
    # (
    #     curl $"https://generativelanguage.googleapis.com/v1beta2/models/text-bison-001:generateText?key=($env.PALM_API_KEY)"
    #     -H 'Content-Type: application/json'
    #     -X POST
    #     -d '{
    #         "prompt": {
    #               "text": "Write a story about a magic backpack."
    #               },
    #         "temperature": 1.0,
    #         "candidate_count": 3}'
    # )
}

# unused
#
# Completion API call.
export def "api completion" [
    model: string # ID of the model to use.
    --prompt: string # The prompt(s) to generate completions for
    --suffix: string # The suffix that comes after a completion of inserted text.
    --max-tokens: int # The maximum number of tokens to generate in the completion.
    --temperature: number # The temperature used to control the randomness of the completion.
    --top-p: number # The top-p used to control the randomness of the completion.
    --n: int # How many completions to generate for each prompt. Use carefully, as it's a token eater.
    --logprobs: int # Include the log probabilities on the logprobs most likely tokens, as well the chosen tokens.
    --echo # Include the prompt in the returned text.
    --stop: string # A list of tokens that, if encountered, will stop the completion.
    --frequency-penalty: number # A penalty to apply to each token that appears more than once in the completion.
    --presence-penalty: number # A penalty to apply if the specified tokens don't appear in the completion.
    --best-of: int # Generates best_of completions server-side and returns the "best" (the one with the highest log probability per token). Use carefully, as it's a token eater.
    --logit-bias: record # A record to modify the likelihood of specified tokens appearing in the completion
    --user: string # A unique identifier representing your end-user.
] {
    # See https://platform.openai.com/docs/api-reference/completions/create
    let params = {model: $model}
    | add_param "prompt" $prompt
    | add_param "suffix" $suffix
    | add_param "max_tokens" $max_tokens
    | add_param "temperature" $temperature
    | add_param "top_p" $top_p
    | add_param "n" $n
    | add_param "logprobs" $logprobs
    | add_param "echo" $echo
    | add_param "stop" $stop
    | add_param "frequency_penalty" $frequency_penalty
    | add_param "presence_penalty" $presence_penalty
    | add_param "best_of" $best_of
    | add_param "logit_bias" $logit_bias
    | add_param "user" $user

    http post "https://api.openai.com/v1/completions" -H ["Authorization" $"Bearer (get-api)"] -t 'application/json' $params
}
