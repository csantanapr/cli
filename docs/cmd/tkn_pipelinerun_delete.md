## tkn pipelinerun delete

Delete a pipelinerun in a namespace

***Aliases**: rm*

### Usage

```
tkn pipelinerun delete
```

### Synopsis

Delete a pipelinerun in a namespace

### Examples


# Delete a PipelineRun of name 'foo' in namespace 'bar'
tkn pipelinerun delete foo -n bar

tkn pr rm foo -n bar",


### Options

```
      --allow-missing-template-keys   If true, ignore any errors in templates when a field or map key is missing in the template. Only applies to golang and jsonpath output formats. (default true)
  -f, --force                         Whether to force deletion (default: false)
  -h, --help                          help for delete
  -o, --output string                 Output format. One of: json|yaml|name|go-template|go-template-file|template|templatefile|jsonpath|jsonpath-file.
      --template string               Template string or path to template file to use when -o=go-template, -o=go-template-file. The template format is golang templates [http://golang.org/pkg/text/template/#pkg-overview].
```

### Options inherited from parent commands

```
  -k, --kubeconfig string   kubectl config file (default: $HOME/.kube/config)
  -n, --namespace string    namespace to use (default: from $KUBECONFIG)
```

### SEE ALSO

* [tkn pipelinerun](tkn_pipelinerun.md)	 - Manage pipelineruns

