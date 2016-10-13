import
  streams, os


proc readCStr (self: Stream): string =
  result = ""
  while true:
    let
      c = self.readChar()
    if c == '\0':
      break
    result.add  c

proc rip2obj (rip, obj: string) =
  var
    posX_Idx = 0
    posY_Idx = 0
    posZ_Idx = 0
    normX_Idx = 0
    normY_Idx = 0
    normZ_Idx = 0
    tc0_U_Idx = 0
    tc0_V_Idx = 0

  let
    input = newFileStream (rip, fmRead)
  if input == nil:
    raise newException (Exception, "Failed to open file: " & rip)

  let
    signature = cast[uint32](input.readInt32())
    version = cast[uint32](input.readInt32())
    faceCount = cast[uint32](input.readInt32())
    vertexCount = cast[uint32](input.readInt32())
    vertexSize = cast[uint32](input.readInt32())
    textureFileCount = cast[uint32](input.readInt32())
    shaderFileCount = cast[uint32](input.readInt32())
    vertexAttributeCount = cast[uint32](input.readInt32())

  if 0xdeadc0de != signature.int:
    raise newException (Exception, "Sorry, this file signature isn't recognized. Ninjaripper .rip expected.")

  if 4 != version.int:
    raise newException (Exception, "Sorry, only version 4 Ninjaripper .rip files are supported.")

  var
    tempPosIdx = 0   # Get only first index attribute flag
    tempNormalIdx = 0
    tempTexCoordIdx = 0

  # Read Vertex Attributes:
  var
    vertexAttribTypesArray = newSeq[uint32]()
  for i in 0..<vertexAttributeCount:
    let
      semantic = input.readCStr()

      semanticIndex = cast[uint32](input.readInt32())
      offset = cast[uint32](input.readInt32())
      size = cast[uint32](input.readInt32())
      typeMapElements = cast[uint32](input.readInt32())

    for j in 0..<typeMapElements:
      vertexAttribTypesArray.add  cast[uint32](input.readInt32())

    if "POSITION" == semantic and 0 == tempPosIdx:
      # Get as "XYZ_"
      posX_Idx = offset.int div 4
      posY_Idx = posX_Idx.int + 1
      posZ_Idx = posX_Idx.int + 2

      tempPosIdx += 1
    elif "NORMAL" == semantic and 0 == tempNormalIdx:
      normX_Idx = offset.int div 4
      normY_Idx = normX_Idx.int + 1
      normZ_Idx = normX_Idx.int + 2
      tempNormalIdx += 1
    elif "TEXCOORD" == semantic and 0 == tempTexCoordIdx:
      tc0_U_Idx = offset.int div 4
      tc0_V_Idx = tc0_U_Idx.int + 1
      tempTexCoordIdx += 1

  # textures
  var
    textureFiles = newSeq[string]()
  for i in 0..<textureFileCount:
    textureFiles.add  input.readCStr()

  # shaders
  var
    shaderFiles = newSeq[string]()
  for i in 0..<shaderFileCount:
    shaderFiles.add  input.readCStr()

  # faces
  type
    Face = array[3, uint32]

  var
    faceArray = newSeq[Face]()
  for i in 0..<faceCount:
    faceArray.add (
      [cast[uint32](input.readInt32()), cast[uint32](input.readInt32()), cast[uint32](input.readInt32())]
    )

  # vertices
  type
    Vec3 = array[3, float32]
    Vec2 = array[2, float32]
  var
    vertArray = newSeq[Vec3]()
    normalArray = newSeq[Vec3]()
    uvArray = newSeq[Vec2]()
    typesCount = vertexAttribTypesArray.len()
  for i in 0..<vertexCount:
    var
      vx = 0.0'f32
      vy = 0.0'f32
      vz = 0.0'f32
      nx = 0.0'f32
      ny = 0.0'f32
      nz = 0.0'f32
      tu = 0.0'f32
      tv = 0.0'f32

    for j in 0..<typesCount:
      let
        elementType = vertexAttribTypesArray[j]
      var
        pos = 0.0'f32
      case elementType
      of 0:
        pos = input.readFloat32()
      of 1:
        pos = cast[uint32](input.readInt32()).float32
      of 2:
        pos = input.readInt32().float32
      else:
        raise newException (Exception, "Unknown vertex element type: " & $elementType)

      if   j == posX_Idx: vx = pos
      elif j == posY_Idx: vy = pos
      elif j == posZ_Idx: vz = pos
      elif j == normX_Idx: nx = pos
      elif j == normY_Idx: ny = pos
      elif j == normZ_Idx: nz = pos
      elif j == tc0_U_Idx: tu = pos
      elif j == tc0_V_Idx: tv = 1'f32 - pos

    vertArray.add ([vx, vy, vz])
    normalArray.add ([nx, ny, nz])
    uvArray.add ([tu, tv])


  let
    inputDir = rip.splitFile.dir
    outputDir = obj.splitFile.dir

    base = obj.splitFile.name
    mtl = obj.splitFile.name & ".mtl"
    oObj = newFileStream (obj, fmWrite)
  if oObj == nil:
    raise newException (Exception, "Failed to open destination file!")

  for tex in textureFiles:
    oObj.write ("mtllib " & mtl & "\r\n")
    oObj.write ("usemtl " & tex & "\r\n")
  for v in vertArray:
    oObj.write ("v " & $v[0] & " " & $v[1] & " " & $v[2] & "\r\n")
  for v in normalArray:
    oObj.write ("vn " & $v[0] & " " & $v[1] & " " & $v[2] & "\r\n")
  for v in uvArray:
    oObj.write ("vt " & $v[0] & " " & $v[1] & "\r\n")

  for face in faceArray:
    oObj.write ("f")
    for v in face:
      oObj.write (" " & $(v+1) & "/" & $(v+1) & "/" & $(v+1))
    oObj.write ("\r\n")

  oObj.close()

  let
    oMtl = newFileStream (outputDir / mtl, fmWrite)
  if oMtl == nil:
    raise newException (Exception, "Failed to open destination file!")

  for tex in textureFiles:
    oMtl.write ("newmtl " & tex & "\r\n")
    oMtl.write ("Ka 1.000 1.000 1.000\r\nKd 1.000 1.000 1.000\r\nKs 0.000 0.000 0.000\r\nd 1.0\r\nillum 2\r\n")
    oMtl.write ("map_Ka " & tex & "\r\n")
    oMtl.write ("map_Kd " & tex & "\r\n")
    oMtl.write ("map_Ks " & tex & "\r\n")

    # Copy the .dds textures over:
    (inputDir / tex).copyFile (outputDir / tex)
  oMtl.close()



if paramCount() < 2:
  echo "Usage: rip2obj [FILE/DIR] [DIR]"
  quit (QuitSuccess)

let
  src = paramStr (1)
  dst = paramStr (2)
dst.createDir()
if src.dirExists():
  for file in walkFiles (src / "*.rip"):
    let
      obj = file.splitFile.name & ".obj"
    file.rip2obj (dst / obj)
elif src.fileExists():
  let
    obj = src.splitFile.name & ".obj"
  src.rip2obj (dst / obj)
else:
  echo src, " could not be found!"
  quit (QuitFailure)