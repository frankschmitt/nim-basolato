import json, strformat, options, strutils, macros
import jester except redirect, setCookie, resp
import base, response, logger, errorPage
from controller import redirect, render, errorRedirect
from private import
  middleware#, http404Route, exceptionRoute, response, redirect, render,
  #errorRedirect

export jester except redirect, setCookie, resp
export redirect, render, errorRedirect
export
  base, response, middleware#, http404Route, exceptionRoute
  #redirect, render, errorRedirect


template route*(rArg: Response) =
  block:
    let r = rArg
    var newHeaders = r.headers
    case r.responseType:
    of String:
      newHeaders.add(("Content-Type", "text/html;charset=utf-8"))
    of Json:
      newHeaders.add(("Content-Type", "application/json"))
      r.bodyString = $(r.bodyJson)
    of Redirect:
      logger($r.status & &"  {request.ip}  {request.reqMethod}  {request.path}")
      newHeaders.add(("Location", r.url))
      resp r.status, newHeaders, ""

    if r.status == Http200:
      logger($r.status & &"  {request.ip}  {request.reqMethod}  {request.path}")
      logger($newHeaders)
    elif r.status.is4xx() or r.status.is5xx():
      echoErrorMsg($request.params)
      echoErrorMsg($r.status & &"  {request.ip}  {request.reqMethod}  {request.path}")
      echoErrorMsg($newHeaders)
    resp r.status, newHeaders, r.bodyString

proc joinHeader(headers:openArray[Headers]): Headers =
  ## join seq and children tuple if each headers have same key in child tuple
  ##
  ## .. code-block:: nim
  ##    let t1 = @[("key1", "val1"),("key2", "val2")]
  ##    let t2 = @[("key1", "val1++"),("key3", "val3")]
  ##    let t3 = joinHeader([t1, t2])
  ##
  ##    echo t3
  ##    >> @[
  ##      ("key1", "val1, val1++"),
  ##      ("key2", "val2"),
  ##      ("key3", "val3"),
  ##    ]
  ##
  var newHeader: Headers
  var tmp = result.toTable
  for header in headers:
    let headerTable = header.toOrderedTable
    for key, value in headerTable.pairs:
      if tmp.hasKey(key):
        tmp[key] = [tmp[key], headerTable[key]].join(", ")
      else:
        tmp[key] = headerTable[key]
  for key, val in tmp.pairs:
    newHeader.add(
      (key:key, val:val)
    )
  return newHeader


template route*(respinseArg:Response,
                headersArg:openArray[Headers]) =
  block:
    let response = respinseArg
    var headersMiddleware = @headersArg
    var newHeaders: Headers
    headersMiddleware.add(response.headers) # headerMiddleware + headerController
    newHeaders = joinHeader(headersMiddleware)
    case response.responseType:
    of String:
      newHeaders.add(("Content-Type", "text/html;charset=utf-8"))
    of Json:
      newHeaders.add(("Content-Type", "application/json"))
      response.bodyString = $(response.bodyJson)
    of Redirect:
      logger($response.status & &"  {request.ip}  {request.reqMethod}  {request.path}")
      newHeaders.add(("Location", response.url))
      resp response.status, newHeaders, ""

    if response.status == Http200:
      logger($response.status & &"  {request.ip}  {request.reqMethod}  {request.path}")
      logger($newHeaders)
    elif response.status.is4xx() or response.status.is5xx():
      echoErrorMsg($response.status & &"  {request.ip}  {request.reqMethod}  {request.path}")
      echoErrorMsg($newHeaders)
    resp response.status, newHeaders, response.bodyString


macro createHttpCodeError():untyped =
  var strBody = ""
  for num in errorStatusArray:
    strBody.add(fmt"""
of "Error{num.repr}":
  return Http{num.repr}
""")
  return parseStmt(fmt"""
case $exception.name
{strBody}
else:
  return Http500
""")

proc checkHttpCode(exception:ref Exception):HttpCode =
  ## Generated by macro createHttpCodeError
  ## List is httpCodeArray
  ## .. code-block:: nim
  ##   case $exception.name
  ##   of Error505:
  ##     return Http505
  ##   of Error504:
  ##     return Http504
  ##   of Error503:
  ##     return Http503
  ##   .
  ##   .
  createHttpCodeError

template exceptionRoute*(pagePath="") =
  defer: GCunref exception
  let status = checkHttpCode(exception)
  if status.is4xx() or status.is5xx():
    echoErrorMsg($request.params)
    echoErrorMsg($status & &"  {request.reqMethod}  {request.ip}  {request.path}  {exception.msg}")
    if pagePath == "":
      route(render(errorPage(status, exception.msg)))
    else:
      route(render(html(pagePath)))
  else:
    route(errorRedirect(exception.msg))

template http404Route*(pagePath="") =
  if not request.path.contains("favicon"):
    echoErrorMsg(&"{$Http404}  {request.ip}  {request.path}")
  if pagePath == "":
    route(render(errorPage(Http404, "route not match")))
  else:
    route(render(html(pagePath)))