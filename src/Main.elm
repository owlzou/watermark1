port module Main exposing (main)

import Array exposing (Array)
import Browser
import Canvas
import Canvas.Texture as Texture
import File exposing (File)
import File.Select as Select
import Html exposing (Html, div, span, text)
import Html.Attributes exposing (checked, class, disabled, href, name, placeholder, rel, style, value)
import Html.Events exposing (on, onClick, onInput)
import Json.Decode as D
import Json.Encode as E
import Model as M exposing (BasicImageState(..), FormatData, ImageType(..), Model, Watermark, WatermarkType(..))
import Render exposing (renderImage, renderText)
import Task
import UI.Color exposing (ColorType(..))
import UI.Icons as Icons
import UI.Main exposing (..)
import UI.Size as Size



-- MAIN


main : Program (List String) Model Msg
main =
    Browser.element { init = init, update = update, view = view, subscriptions = subscriptions }



-- MODEL


init : List String -> ( Model, Cmd Msg )
init fmts =
    ( M.initModel fmts, Cmd.none )



-- UPDATE


type Msg
    = ImageUpload ImageType --上传图片
    | ImageRead ImageType File --读取图片
    | ImageLoaded ImageType String String --图片读取完成
    | ImageOnLoad ImageType Int (Maybe Texture.Texture) --图片纹理加载完成
    | RemoveImage --移除当前底图
    | WatermarkInput String -- 文字输入
    | WatermarkSelected Int --选择了某个文字水印
    | WatermarkAdd WatermarkType --水印添加
    | WatermarkRemove --移除水印
    | UpdateWatermark Watermark
    | UpdateFont Watermark --更新水印并重新测量字体宽度
    | UpdateFormat FormatData
    | UpdateFontCDN String
    | SaveImage
    | RecvTextWidth Float


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        -- 加载图片
        ImageUpload tp ->
            ( model
            , Select.file M.supportedUploadFormat (ImageRead tp)
            )

        ImageRead tp file ->
            ( model, Task.perform (ImageLoaded tp (File.name file)) (File.toUrl file) )

        ImageLoaded tp name data ->
            case tp of
                Base ->
                    ( { model | imageName = name, imageUrl = data, imageState = Loaded }, Cmd.none )

                WatermarkImage ->
                    let
                        newWm =
                            M.initWatermark Image data model.imageSize

                        ( newWatermark, index ) =
                            case model.watermark of
                                Just watermark ->
                                    ( Array.push { newWm | text = name } watermark, Array.length watermark )

                                Nothing ->
                                    ( Array.fromList [ { newWm | text = name } ], 0 )
                    in
                    ( { model | watermark = Just newWatermark, selectedIndex = index }, Cmd.none )

        ImageOnLoad tp number maybeTex ->
            case maybeTex of
                Just tex ->
                    let
                        size =
                            Texture.dimensions tex
                    in
                    case tp of
                        Base ->
                            ( { model | imageTexture = Just tex, imageSize = size, log = model.imageName ++ " " ++ M.printSize size }, Cmd.none )

                        WatermarkImage ->
                            case model.watermark of
                                Just watermarks ->
                                    case Array.get number watermarks of
                                        Just watermark ->
                                            ( { model | watermark = Just (Array.set number { watermark | texture = Just tex, size = size } watermarks) }, Cmd.none )

                                        Nothing ->
                                            ( model, Cmd.none )

                                Nothing ->
                                    ( model, Cmd.none )

                Nothing ->
                    ( { model | log = "纹理加载失败" }, Cmd.none )

        RemoveImage ->
            ( { model | imageUrl = "", log = "未上传图片", imageSize = { width = 0, height = 0 }, imageState = None }, Cmd.none )

        -- 水印处理相关
        WatermarkInput text ->
            ( { model | watermarkInput = text }, Cmd.none )

        WatermarkSelected number ->
            ( { model | selectedIndex = number }, Cmd.none )

        WatermarkAdd type_ ->
            case type_ of
                Image ->
                    ( model, Select.file M.supportedUploadFormat (ImageRead WatermarkImage) )

                Text ->
                    if String.trim model.watermarkInput == "" || model.imageState == None then
                        ( model, Cmd.none )

                    else
                        let
                            newText =
                                M.initWatermark Text model.watermarkInput model.imageSize

                            ( newWatermark, index ) =
                                case model.watermark of
                                    Just text ->
                                        ( Array.push newText text, Array.length text )

                                    Nothing ->
                                        ( Array.fromList [ newText ], 0 )
                        in
                        ( { model | watermark = Just newWatermark, watermarkInput = "", selectedIndex = index }, measureText (M.encodeText newText) )

        WatermarkRemove ->
            case model.watermark of
                Just w ->
                    ( { model | watermark = Just (arrRemove model.selectedIndex w), selectedIndex = -1 }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        UpdateWatermark wm ->
            ( M.updateWatermark wm model, Cmd.none )

        UpdateFont wm ->
            ( M.updateWatermark wm model, measureText (M.encodeText wm) )

        --具体修改
        UpdateFormat fmt ->
            ( { model | format = fmt }, Cmd.none )

        UpdateFontCDN cdn ->
            ( { model | fontCDN = cdn }, Cmd.none )

        SaveImage ->
            ( model, saveImage <| M.encodeImage model )

        RecvTextWidth w ->
            ( M.updateSize w model, Cmd.none )



-- VIEW


view : Model -> Html Msg
view model =
    div [ UI.Color.hasBackground White ]
        [ Html.node "link" [ href model.fontCDN, rel "stylesheet" ] []
        , columns
            []
            [ column [ Size.width 4 ] [ menuLeft model ]
            , column [ Size.width 8 ] [ workTable model, menuDown model ]
            ]
        ]



--菜单


menuLeft : Model -> Html Msg
menuLeft model =
    let
        available =
            disabled (model.imageState /= Loaded)
    in
    section
        []
        [ container [ style "width" "100%" ]
            [ title [] [ text "Watermark+1" ]
            , notification [ UI.Color.is InfoLight ] [ text model.log ]
            , field [] [ label [] [ text "水印列表" ] ]
            , field []
                [ selectMultiple 8
                    [ style "width" "100%" ]
                    (case model.watermark of
                        Just watermark ->
                            Array.map (\t -> t.text) watermark |> Array.toList

                        Nothing ->
                            []
                    )
                    (\i -> i == model.selectedIndex)
                    WatermarkSelected
                ]
            , fieldAddon []
                [ input [ onInput WatermarkInput, placeholder "请输入文字水印……", value model.watermarkInput ] []
                , iconButton Icons.plus [ available, onClick (WatermarkAdd Text) ] [ text "文字" ]
                ]
            , fieldGroup []
                [ iconButton Icons.plus [ available, onClick (WatermarkAdd Image) ] [ text "图片水印" ]
                , iconButton Icons.trash2 [ available, UI.Color.is DangerLight, onClick WatermarkRemove ] [ text "删除" ]
                ]
            , field [] [ label [] [ text "输出格式" ] ]

            -- 选择图片格式
            , field [ class "output-format-radio" ]
                [ control [] <|
                    List.map
                        (\tp ->
                            let
                                notable =
                                    List.length (List.filter (\t -> t == tp.mime) model.supportedFormat) == 0
                            in
                            if notable then
                                tooltip "您的浏览器不支持转换该格式"
                                    []
                                    [ radio []
                                        [ checked (model.format == tp)
                                        , name "convert"
                                        , disabled True
                                        ]
                                        [ label [] [ text tp.name, Icons.helpCircle ] ]
                                    ]

                            else
                                radio [ onClick (UpdateFormat tp) ]
                                    [ checked (model.format == tp)
                                    , name "convert"
                                    ]
                                    [ label [] [ text tp.name ] ]
                        )
                        M.formatData
                ]
            , field [] [ label [] [ text "字体CDN" ] ]
            , field [] [ control [] [ input [ value model.fontCDN, onInput UpdateFontCDN ] [] ] ]
            ]
        ]


menuDown : Model -> Html Msg
menuDown model =
    let
        available =
            disabled (model.imageState /= Loaded)

        {-
           zoom =
               model.imageSize.height * 100 // 400
        -}
    in
    section
        [ class "menu-down" ]
        [ container []
            [ fieldGroup [ class "base-menu" ]
                [ iconButton Icons.trash2 [ UI.Color.is DangerLight, onClick RemoveImage, available ] [ text "移除当前图片" ]

                {- , iconButton Icons.crop [ available ] [ text "裁剪" ]
                   , div [ style "display" "flex" ] [ Icons.zoomOut, slider 0 100 zoom [] [], Icons.zoomIn ]
                -}
                ]
            , case model.watermark of
                Just arr ->
                    case Array.get model.selectedIndex arr of
                        Just index ->
                            textModify index

                        Nothing ->
                            div [] []

                Nothing ->
                    div [] []
            ]
        , columns [] [ column [] [ iconButton Icons.download [ UI.Color.is Primary, class "is-fullwidth", onClick SaveImage ] [ text "保存" ] ] ]
        ]



-- 文字水印修改


textModify : Watermark -> Html Msg
textModify cur =
    let
        ( px, py ) =
            cur.position

        ( gx, gy ) =
            cur.gap
    in
    div []
        [ columns []
            [ column []
                [ fieldHorizontal []
                    "旋转"
                    [ slider 0 360 (round cur.rotation) [ onChange (\rot -> UpdateWatermark { cur | rotation = Maybe.withDefault 0 (String.toFloat rot) }) ] []
                    , label [] [ text (String.fromFloat cur.rotation ++ "°") ]
                    ]
                ]
            , column []
                [ fieldHorizontal []
                    "坐标"
                    [ input [ value px, onInput (\t -> UpdateWatermark { cur | position = ( t, py ) }), disabled (cur.tiled == True) ] []
                    , input [ value py, onInput (\t -> UpdateWatermark { cur | position = ( px, t ) }), disabled (cur.tiled == True) ] []
                    ]
                ]
            ]
        , case cur.type_ of
            Text ->
                columns []
                    [ column [] [ fieldHorizontal [] "颜色" [ input [ value cur.color, onInput (\t -> UpdateWatermark { cur | color = t }), placeholder "#000000" ] [] ] ]
                    , column [ Size.width 6 ]
                        [ fieldHorizontal []
                            "字体"
                            [ input [ value cur.font, onInput (\t -> UpdateFont { cur | font = t }), placeholder "serif" ] []
                            , input
                                [ value cur.fontSize
                                , onInput (\t -> UpdateFont { cur | fontSize = t })
                                , placeholder "24"
                                ]
                                []
                            ]
                        ]
                    ]

            Image ->
                span [] []
        , columns []
            [ column [ Size.width 6 ]
                [ fieldHorizontal []
                    "透明"
                    [ slider 0 100 cur.opacity [ onChange (\op -> UpdateWatermark { cur | opacity = Maybe.withDefault 0 (String.toInt op) }) ] []
                    , label [] [ text (String.fromInt cur.opacity ++ "%") ]
                    ]
                ]
            , case cur.type_ of
                Text ->
                    column [] [ fieldHorizontal [] "内容" [ input [ value cur.text, onInput (\t -> UpdateFont { cur | text = t }) ] [] ] ]

                Image ->
                    column [] [ fieldHorizontal [] "尺寸" [ input [ value cur.fontSize, onInput (\t -> UpdateWatermark { cur | fontSize = t }), placeholder "1" ] [] ] ]
            ]
        , columns []
            [ column [] [ fieldHorizontal [] "平铺" [ checkbox cur.tiled "" [ onClick (UpdateWatermark { cur | tiled = Basics.not cur.tiled }) ] ] ]
            , column []
                [ fieldHorizontal []
                    "间距"
                    [ input
                        [ value gx
                        , onInput (\t -> UpdateWatermark { cur | gap = ( t, gy ) })
                        , disabled (Basics.not cur.tiled)
                        , placeholder "0"
                        ]
                        []
                    , input
                        [ value gy
                        , onInput (\t -> UpdateWatermark { cur | gap = ( gx, t ) })
                        , disabled (Basics.not cur.tiled)
                        , placeholder "0"
                        ]
                        []
                    ]
                ]
            ]
        ]



-- 图片显示


workTable : Model -> Html Msg
workTable model =
    let
        renderWatermark : Watermark -> List Canvas.Renderable
        renderWatermark watermark =
            case watermark.type_ of
                Text ->
                    renderText model watermark

                Image ->
                    renderImage model watermark

        textureWatermark index mark =
            case mark.type_ of
                Image ->
                    [ Texture.loadFromImageUrl mark.url (ImageOnLoad WatermarkImage index) ]

                Text ->
                    []
    in
    section
        []
        [ case model.imageState of
            None ->
                uploadFrame

            Loaded ->
                container
                    [ class "image-container" ]
                    [ Canvas.toHtmlWith
                        { width = round model.imageSize.width
                        , height = round model.imageSize.height
                        , textures =
                            List.append
                                [ Texture.loadFromImageUrl model.imageUrl (ImageOnLoad Base 0) ]
                                (case model.watermark of
                                    Just arr ->
                                        List.concat <|
                                            Array.toList <|
                                                Array.indexedMap textureWatermark arr

                                    Nothing ->
                                        []
                                )
                        }
                        []
                        (case model.imageTexture of
                            Just tex ->
                                List.append
                                    [ Canvas.texture [] ( 0, 0 ) tex ]
                                    (case model.watermark of
                                        Just arr ->
                                            List.concatMap renderWatermark (Array.toList arr)

                                        Nothing ->
                                            []
                                    )

                            Nothing ->
                                []
                        )
                    ]
        ]


uploadFrame : Html Msg
uploadFrame =
    container
        [ class "has-text-primary"
        , class "upload-frame"
        ]
        [ div
            [ onClick (ImageUpload Base) ]
            [ Icons.image
            , span [] [ text "点击上传" ]
            ]
        ]



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    receiveTextWidth RecvTextWidth



-- PORTS


port saveImage : E.Value -> Cmd msg


port measureText : E.Value -> Cmd msg


port receiveTextWidth : (Float -> msg) -> Sub msg



--Helper------------------------------------------------------------------------------------------------


onChange : (String -> Msg) -> Html.Attribute Msg
onChange number =
    on "change" <| D.map number <| D.at [ "target", "value" ] D.string


arrRemove : Int -> Array a -> Array a
arrRemove index arr =
    if index < Array.length arr && index >= 0 then
        Array.append
            (Array.slice 0 index arr)
            (Array.slice (index + 1) (Array.length arr) arr)

    else
        arr
