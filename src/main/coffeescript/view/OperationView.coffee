class OperationView extends Backbone.View
  events: {
  'submit .sandbox'         : 'submitOperation'
  'click .submit'           : 'submitOperation'
  'click .response_hider'   : 'hideResponse'
  'click .toggleOperation'  : 'toggleOperationContent'
  }

  initialize: ->

  render: ->
    isMethodSubmissionSupported = true #jQuery.inArray(@model.method, @model.supportedSubmitMethods) >= 0
    @model.isReadOnly = true unless isMethodSubmissionSupported

    $(@el).html(Handlebars.templates.operation(@model))

    operationModels = ''

    if @model.responseClassSignature and !@model.isResponseClassPrimitive
      signatureModel =
        sampleJSON: @model.responseSampleJSON
        isParam: false
        signature: if SwaggerUiConfig.showParameterDataTypeColumn then @model.responseClassSignature else "<span class='strong'>#{@model.type}</span>"

      unless SwaggerUiConfig.showParameterDataTypeColumn
        operationModels = @model.responseClassSignature

      responseSignatureView = new SignatureView({model: signatureModel, tagName: 'div'})
      $('#response-class', $(@el)).append responseSignatureView.render().el
    else if @model.type
      $('#response-class', $(@el)).html(@model.type)
    else
      $('#response-class', $(@el)).html('(None)')

    contentTypeModel =
      isParam: false

    contentTypeModel.consumes = @model.consumes
    contentTypeModel.produces = @model.produces

    for param in @model.parameters
      type = param.type || param.dataType
      if type.toLowerCase() == 'file'
        if !contentTypeModel.consumes
          console.log "set content type "
          contentTypeModel.consumes = 'multipart/form-data'

      unless param.isPrimitive or SwaggerUiConfig.showParameterDataTypeColumn
        unless param.signature == null
          if operationModels != ''
            operationModels += '<br/>'
          operationModels += param.signature

    responseContentTypeView = new ResponseContentTypeView({model: contentTypeModel})
    $('.response-content-type', $(@el)).append responseContentTypeView.render().el

    # Render each parameter
    @addParameter param, contentTypeModel.consumes for param in @model.parameters

    # Render each response code
    @addStatusCode statusCode for statusCode in @model.responseMessages

    if operationModels == ''
      operationModels = '(None)'

    $('#operation-models', $(@el)).html(operationModels)

    @

  addParameter: (param, consumes) ->
    # Render a parameter
    param.consumes = consumes
    paramView = new ParameterView({model: param, tagName: 'tr', readOnly: @model.isReadOnly})
    $('.operation-params', $(@el)).append paramView.render().el

  addStatusCode: (statusCode) ->
    # Render status codes
    statusCodeView = new StatusCodeView({model: statusCode, tagName: 'tr'})
    $('.operation-status', $(@el)).append statusCodeView.render().el

  submitOperation: (e) ->
    e?.preventDefault()
    # Check for errors
    form = $('.sandbox', $(@el))
    error_free = true
    form.find("input.required").each ->
      $(@).removeClass "error"
      if jQuery.trim($(@).val()) is ""
        $(@).addClass "error"
        $(@).wiggle
          callback: => $(@).focus()
        error_free = false

    # if error free submit it
    if error_free
      map = {}
      opts = {parent: @}

      isFileUpload = false

      for o in form.find("input")
        if(o.value? && jQuery.trim(o.value).length > 0)
          map[o.name] = o.value
        if o.type is "file"
          isFileUpload = true

      for o in form.find("textarea")
        if(o.value? && jQuery.trim(o.value).length > 0)
          map["body"] = o.value

      for o in form.find("select")
        val = this.getSelectedValue o
        if(val? && jQuery.trim(val).length > 0)
          map[o.name] = val

      opts.responseContentType = $("div select[name=responseContentType]", $(@el)).val()
      unless opts.responseContentType
        if @model.produces and @model.produces.length > 0
          # dropdown might not exist because we don't show it. default to first content type from operation
          opts.responseContentType = @model.produces[0]

      opts.requestContentType = $("div select[name=parameterContentType]", $(@el)).val()
      unless opts.requestContentType
        if @model.consumes and @model.consumes.length > 0
          # dropdown might not exist because we don't show it. default to first content type from operation
          opts.requestContentType = @model.consumes[0]

      $(".response_throbber", $(@el)).show()
      if isFileUpload
        @handleFileUpload map, form
      else
        @model.do(map, opts, @showCompleteStatus, @showErrorStatus, @)

  success: (response, parent) ->
    parent.showCompleteStatus response

  handleFileUpload: (map, form) ->
    for o in form.serializeArray()
      if(o.value? && jQuery.trim(o.value).length > 0)
        map[o.name] = o.value

    # requires HTML5 compatible browser
    bodyParam = new FormData()
    params = 0

    # add params
    for param in @model.parameters
      if param.paramType is 'form'
        if param.type.toLowerCase() isnt 'file' and map[param.name] != undefined
            bodyParam.append(param.name, map[param.name])

    # headers in operation
    headerParams = {}
    for param in @model.parameters
      if param.paramType is 'header'
        headerParams[param.name] = map[param.name]

    log headerParams

    # add files
    for el in form.find('input[type~="file"]')
      if typeof el.files[0] isnt 'undefined'
        bodyParam.append($(el).attr('name'), el.files[0])
        params += 1

    @invocationUrl =
      if @model.supportHeaderParams()
        headerParams = @model.getHeaderParams(map)
        @model.urlify(map, false)
      else
        @model.urlify(map, true)

    $(".request_url", $(@el)).html "<pre>" + @invocationUrl + "</pre>"

    obj =
      type: @model.method
      url: @invocationUrl
      headers: headerParams
      data: bodyParam
      dataType: 'json'
      contentType: false
      processData: false
      error: (data, textStatus, error) =>
        @showErrorStatus(@wrap(data), @)
      success: (data) =>
        @showResponse(data, @)
      complete: (data) =>
        @showCompleteStatus(@wrap(data), @)

    # apply authorizations
    if window.authorizations
      window.authorizations.apply obj

    if params is 0
      obj.data.append("fake", "true");

    jQuery.ajax(obj)
    false
    # end of file-upload nastiness

  # wraps a jquery response as a shred response

  wrap: (data) ->
    headers = {}
    headerArray = data.getAllResponseHeaders().split("\r")
    for i in headerArray
      h = i.split(':')
      if (h[0] != undefined && h[1] != undefined)
        headers[h[0].trim()] = h[1].trim()

    o = {}
    o.content = {}
    o.content.data = data.responseText
    o.headers = headers
    o.request = {}
    o.request.url = @invocationUrl
    o.status = data.status
    o

  getSelectedValue: (select) ->
    if !select.multiple
      select.value
    else
      options = []
      options.push opt.value for opt in select.options when opt.selected
      if options.length > 0
        options.join ","
      else
        null


  # handler for hide response link
  hideResponse: (e) ->
    e?.preventDefault()
    $(".response", $(@el)).slideUp()
    $(".response_hider", $(@el)).fadeOut()


  # Show response from server
  showResponse: (response) ->
    prettyJson = JSON.stringify(response, null, "\t").replace(/\n/g, "<br>")
    $(".response_body", $(@el)).html escape(prettyJson)

  # Show error from server
  showErrorStatus: (data, parent) ->
    parent.showStatus data

  # show the status codes
  showCompleteStatus: (data, parent) ->
    parent.showStatus data

  # Adapted from http://stackoverflow.com/a/2893259/454004
  formatXml: (xml) ->
    reg = /(>)(<)(\/*)/g
    wsexp = /[ ]*(.*)[ ]+\n/g
    contexp = /(<.+>)(.+\n)/g
    xml = xml.replace(reg, '$1\n$2$3').replace(wsexp, '$1\n').replace(contexp, '$1\n$2')
    pad = 0
    formatted = ''
    lines = xml.split('\n')
    indent = 0
    lastType = 'other'
    # 4 types of tags - single, closing, opening, other (text, doctype, comment) - 4*4 = 16 transitions
    transitions =
      'single->single': 0
      'single->closing': -1
      'single->opening': 0
      'single->other': 0
      'closing->single': 0
      'closing->closing': -1
      'closing->opening': 0
      'closing->other': 0
      'opening->single': 1
      'opening->closing': 0
      'opening->opening': 1
      'opening->other': 1
      'other->single': 0
      'other->closing': -1
      'other->opening': 0
      'other->other': 0

    for ln in lines
      do (ln) ->

        types =
          # is this line a single tag? ex. <br />
          single: Boolean(ln.match(/<.+\/>/))
          # is this a closing tag? ex. </a>
          closing: Boolean(ln.match(/<\/.+>/))
          # is this even a tag (that's not <!something>)
          opening: Boolean(ln.match(/<[^!?].*>/))

        [type] = (key for key, value of types when value)
        type = if type is undefined then 'other' else type

        fromTo = lastType + '->' + type
        lastType = type
        padding = ''

        indent += transitions[fromTo]
        padding = ('  ' for j in [0...(indent)]).join('')
        if fromTo == 'opening->closing'
          #substr removes line break (\n) from prev loop
          formatted = formatted.substr(0, formatted.length - 1) + ln + '\n'
        else
          formatted += padding + ln + '\n'

    formatted


  # puts the response data in UI
  showStatus: (response) ->
    if response.content is undefined
        content = response.data
        url = response.url
    else
        content = response.content.data
        url = response.request.url

    if response.headers is undefined
    	headers = response.getHeaders()
    else
    	headers = response.headers

    # if server is nice, and sends content-type back, we can use it
    contentType = if headers && headers["Content-Type"] then headers["Content-Type"].split(";")[0].trim() else null

    if !content
      code = $('<code />').text("no content")
      pre = $('<pre class="json" />').append(code)
    else if contentType is "application/json" || /\+json$/.test(contentType)
      code = $('<code />').text(JSON.stringify(JSON.parse(content), null, "  "))
      pre = $('<pre class="json" />').append(code)
    else if contentType is "application/xml" || /\+xml$/.test(contentType)
      code = $('<code />').text(@formatXml(content))
      pre = $('<pre class="xml" />').append(code)
    else if contentType is "text/html"
      code = $('<code />').html(content)
      pre = $('<pre class="xml" />').append(code)
    else if contentType is "application/pkcs10" or contentType is "application/x-x509-ca-cert" or contentType is "text/plain"
      # these MIME types are just text
      code = $('<code />').html(content)
      pre = $('<pre/>').append(code)
    else if /^image\//.test(contentType)
      pre = $('<img>').attr('src',url)
    else
      try
        # if content type is null or undefined, we'll try to parse it to JSON anyways. This is to work around IE9's lack of CORS support
        if contentType == null
          jsonStr = JSON.stringify(JSON.parse(content), null, "  ")
          code = $('<code />').text(jsonStr)
        else
          throw new Error
      catch error
        code = $('<code />').text("Content-Type '#{contentType}' is not recognized. Content will not be displayed.")
      pre = $('<pre class="json" />').append(code)


    response_body = pre
    $(".request_url", $(@el)).html "<pre>" + url + "</pre>"
    $(".response_code", $(@el)).html "<pre>" + response.status + "</pre>"
    $(".response_body", $(@el)).html response_body
    $(".response_headers", $(@el)).html "<pre>" + JSON.stringify(headers) + "</pre>"
    $(".response", $(@el)).slideDown()
    $(".response_hider", $(@el)).show()
    $(".response_throbber", $(@el)).hide()
    hljs.highlightBlock($('.response_body', $(@el))[0])

  toggleOperationContent: ->
    elem = $('#' + Docs.escapeResourceName(@model.resourceName) + "_" + @model.nickname + "_" + @model.method + "_" + @model.number + "_content")
    if elem.is(':visible') then Docs.collapseOperation(elem) else Docs.expandOperation(elem)
