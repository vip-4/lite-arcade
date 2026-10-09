// 使用 Windows 内置 JScript 引擎对 ES5 脚本做语法编译校验（不执行）
// 以 UTF-8 读取，避免 ANSI 代码页把中文破坏成非法字符
var fso = new ActiveXObject("Scripting.FileSystemObject");
var root = fso.GetFolder(".");
var files = [];

collect(root);

function collect(folder) {
    var e = new Enumerator(folder.Files);
    for (; !e.atEnd(); e.moveNext()) {
        var f = e.item();
        if (/\.js$/i.test(f.Name)) files.push(f.Path);
    }
    var s = new Enumerator(folder.SubFolders);
    for (; !s.atEnd(); s.moveNext()) collect(s.item());
}

function readUtf8(path) {
    var st = new ActiveXObject("ADODB.Stream");
    st.Type = 2;
    st.Charset = "utf-8";
    st.Open();
    st.LoadFromFile(path);
    var text = st.ReadText(-1);
    st.Close();
    // 去掉 UTF-8 BOM
    if (text.charCodeAt(0) === 0xFEFF) text = text.substring(1);
    return text;
}

var bad = 0;
for (var i = 0; i < files.length; i++) {
    var code = readUtf8(files[i]);
    // JScript 无法解析 astral 平面字符（emoji 代理对），编译前替换为占位符
    code = code.replace(/[\uD800-\uDBFF][\uDC00-\uDFFF]/g, "\uFFFD");
    try {
        new Function(code);
        WScript.Echo("OK    " + files[i]);
    } catch (ex) {
        bad++;
        WScript.Echo("FAIL  " + files[i] + "  =>  " + ex.message);
    }
}
WScript.Echo("---- checked " + files.length + " files, " + bad + " failed ----");
