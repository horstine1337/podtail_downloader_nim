#[
  Horstine1337@safe-mail.net 29. Mar. 2022
  To compile in console use
  $ nim c -d:ssl ptdownloader.nim
  To cross compile to windows from a linux machine using the MinGW-w64 toolchain
  $ nim c -d:ssl -d:mingw ptdownloader.nim
  Additionally you can check https://nim-lang.org/docs/nimc.html
  

  Boost Software License - Version 1.0 - August 17th, 2003

  Permission is hereby granted, free of charge, to any person or organization
  obtaining a copy of the software and accompanying documentation covered by
  this license (the "Software") to use, reproduce, display, distribute,
  execute, and transmit the Software, and to prepare derivative works of the
  Software, and to permit third-parties to whom the Software is furnished to
  do so, all subject to the following:

  The copyright notices in the Software and this entire statement, including
  the above license grant, this restriction and the following disclaimer,
  must be included in all copies of the Software, in whole or in part, and
  all derivative works of the Software, unless such copies or derivative
  works are solely in the form of machine-executable object code generated by
  a source language processor.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
  SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
  FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
  ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
  DEALINGS IN THE SOFTWARE.
]#

import httpClient     #To fetching html from some URL
import std/strutils   #For substrings
import std/os         #To check if directory or file exists
import std/re         #For regex search
import std/htmlparser #For dom parsing
import std/xmltree    #For dom parsing 
import std/strtabs    #To access dom XmlAttributes

#just initialize for the whole program, as this thing is used multiple times
let client = newHttpClient()

# Download all files from given URLs to given directory
proc downloadLinks(downloadLinks: openArray[string], pathTo: string) =
    if pathTo.isEmptyOrWhitespace :
      echo "No download directory provided."
      return

    if downloadLinks.len == 0 :
      echo "No download links found."
      return

    for link in downloadLinks :
        let index: int = link.rfind("/")
        #if empty string or no '/' was found, ignore the current link
        if index == -1 or link.isEmptyOrWhitespace:
          continue
        let saveTo: string = link[index+1 .. ^1] #^1 means last index. It counts back to front, starting with index 1
        #if the file already exists, ignore
        if fileExists(pathTo & saveTo): continue

        #download and save to given directory
        echo "Downloading " & link & " to " & pathTo & saveTo
        if not dirExists(pathTo): createDir(pathTo)
        client.downloadFile(link, pathTo & saveTo)


# Iterate over all pages for current podcast until "No episodes found".
# Then parse all URLs containing ".mp3" from the downloaded html.
proc findAllDownloadLinksByRegex(podcastUrl: string): seq[string] =
  var done: bool = false
  var curPageNumber: int = 1
  let urlWithParameters: string = podcastUrl & "?page=$1&append=false&sort=latest&q="
  var mp3Reg = re("(?<=href=\\\")https?:\\/\\/?[^ ]*\\.\\w*/.+mp3") # Look ma, magic!
  var ret: seq[string]
  
  while not done:
    let urlForCurrentPage: string = 
      urlWithParameters.format(curPageNumber)
    curPageNumber = curPageNumber + 1
    echo "Searching download links on " & urlForCurrentPage
    let tmpReceivedHtml: string = getContent(client, urlForCurrentPage)
    var matches: seq[string]

    if tmpReceivedHtml.find("<p>No episodes found.</p>") != -1:
      done = true
    else:
      matches = findAll(tmpReceivedHtml, mp3Reg)

    for match in matches:
      echo "Found " & match
      ret.add(match)

  return ret


# Iterate over all pages for current podcast until "No episodes found".
# Find and parse all download URLs by html element.
proc findAllDownloadLinksByDom(podcastUrl: string): seq[string] =
    var done: bool = false
    var curPageNumber: int = 1
    let urlWithParameters: string = podcastUrl & "?page=$1&append=false&sort=latest&q="
    var ret: seq[string]

    while not done:
      let urlForCurrentPage: string = 
        urlWithParameters.format(curPageNumber)
      curPageNumber = curPageNumber + 1

      echo "Searching download links on " & urlForCurrentPage
      let tmpReceivedHtml: string = getContent(client, urlForCurrentPage)

      if tmpReceivedHtml.find("<p>No episodes found.</p>") != -1:
        done = true
      else:
        #In D we had to put some tag around the downloaded html to fix an issue with dom.d
        #I assume the same here; didn't even test without the tags
        var document = parseHtml("<div>" & tmpReceivedHtml & "</div>")
        var curLinks: seq[string]
        for a in document.findAll("a"):
          if a.attrs.hasKey("href") and a.attrs.hasKey("title") and (a.attrs["title"] == "Download" or a.attrs["title"] == "Herunterladen"):
            let curLink: string = a.attrs["href"]
            if not curLink.isEmptyOrWhitespace:
              echo "Found " & curLink
              curLinks.add(curLink)
        ret.add(curLinks)

    echo "Found " & intToStr(ret.len) & " links"
    return ret;


proc writeHelpMessage() =
  #why not simply wysiwyg with r"", like in D. Instead we have to put these new lines everywhere and this whole thing becomes unreadable
  echo "Please specify the podcast URL like \n./ptdownloader https://podtail.com/podcast/NAME/\nIf you want to store the files in a different directory than the working dir,\n./ptdownloader https://podtail.com/podcast/NAME/ ./download/directory/\n\nAlternatively you can set the download lookup to dom,\nwhich will download any href where html attribute title='Download'\n./ptdownloader dom https://podtail.com/podcast/NAME/ ./download/directory/\n\nThe detault will look for URLs ending with '.mp3'."


proc main(args: var seq[string]) =
  var useRegex: bool = true
  var podcastUrl: string = ""
  var links: seq[string]
  var dlDir: string = "./"

  #prepare arguments
  if args.len == 0:
    writeHelpMessage()
    return
  if args[0] == "dom":
    useRegex = false;
    args = args[1..^1]
  if args.len != 0:
    podcastUrl = args[0]
    args = args[1..^1]
  else:
    writeHelpMessage()
  if args.len != 0:
    dlDir = args[0]
    args = args[1..^1]

  #do the work
  if useRegex:
    links = findAllDownloadLinksByRegex(podcastUrl)
  else:
    links = findAllDownloadLinksByDom(podcastUrl)

  downloadLinks(links, dlDir)


#weird flex but ok
if paramCount() > 1:
  var mainArgs: seq[string]
  for i in 1 ..< paramCount()+1:
    mainArgs.add(paramStr(i))
  main(mainArgs)
else:
  writeHelpMessage()