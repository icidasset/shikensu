module Test.Contrib (contribTests) where

import Data.ByteString (ByteString)
import Flow
import System.FilePath (joinPath)
import Test.Helpers
import Test.Tasty
import Test.Tasty.HUnit

import qualified Data.Aeson.Types as Aeson (Value(..))
import qualified Data.ByteString as B (empty)
import qualified Data.ByteString.Char8 as BS (intercalate, pack)
import qualified Data.HashMap.Strict as HashMap (fromList, lookup)
import qualified Data.List as List (head, reverse)
import qualified Data.Text as Text (pack, unpack)
import qualified Data.Text.IO as Text (readFile)
import qualified Data.Text.Encoding as Text (decodeUtf8)
import qualified Shikensu
import qualified Shikensu.Contrib as Contrib
import qualified Shikensu.Contrib.IO as Contrib.IO
import qualified Shikensu.Types as Shikensu


contribTests :: TestTree
contribTests = testGroup
  "Contrib tests"
  [ testClone
  , testExclude
  , testMetadata
  , testPermalink
  , testPrefixDirname
  , testRead
  , testRename
  , testRenameExt
  , testRenderContent
  , testWrite
  ]




-- Test data


list :: Shikensu.Pattern -> IO Shikensu.Dictionary
list pattern = rootPath >>= Shikensu.list [pattern]


example_md :: IO Shikensu.Dictionary
example_md = list "tests/fixtures/example.md"


renderer :: Shikensu.Definition -> Maybe ByteString
renderer def =
  let
    openingTag = BS.pack "<html>"
    closingTag = BS.pack "</html>"
  in
    def
      |> Shikensu.content
      |> fmap (\c -> BS.intercalate B.empty [openingTag, c, closingTag])




-- Tests


testClone :: TestTree
testClone =
  let
    dictionary = fmap (Contrib.clone "example.md" "cloned.md") example_md
    definition = fmap (List.head . List.reverse) dictionary
  in
    testCase "Should `clone`"
      $ definition `rmap` Shikensu.localPath >>= assertEq "cloned.md"



testExclude :: TestTree
testExclude =
  let
    dictionary = fmap (Contrib.exclude "example.md") example_md
    length_ = fmap length dictionary
  in
    testCase "Should `exclude`"
      $ length_ >>= assertEq 0



testMetadata :: TestTree
testMetadata =
  let
    keyA        = Text.pack "title"
    valueA      = Aeson.String (Text.pack "Hello world!")

    keyB        = Text.pack "hello"
    valueB      = Aeson.String (Text.pack "Guardian.")

    keyC        = Text.pack "removed"
    valueC      = Aeson.String (Text.pack "Me.")

    keyBase     = Text.pack "basename"
    valueBase   = Aeson.String (Text.pack "example")

    -- 1. Insert C
    -- 2. Replace with A
    -- 3. Insert B
    dictionary = example_md
      <&> ( Contrib.insertMetadata (HashMap.fromList [ (keyC, valueC) ])
         .> Contrib.replaceMetadata (HashMap.fromList [ (keyA, valueA) ])
         .> Contrib.copyPropsToMetadata
         .> Contrib.insertMetadata (HashMap.fromList [ (keyB, valueB) ])
      )

    definition  = fmap (List.head . List.reverse) dictionary

    lookupTitle = \def -> HashMap.lookup keyA (Shikensu.metadata def)
    lookupHello = \def -> HashMap.lookup keyB (Shikensu.metadata def)
    lookupRemoved = \def -> HashMap.lookup keyC (Shikensu.metadata def)
    lookupBasename = \def -> HashMap.lookup keyBase (Shikensu.metadata def)
  in
    testGroup
      "Metadata"
      [ testCase "Should no longer have `removed` key"
        $ definition `rmap` lookupRemoved >>= assertEq Nothing

      , testCase "Should have `hello` key"
        $ definition `rmap` lookupHello >>= assertEq (Just valueB)

      , testCase "Should have `title` key"
        $ definition `rmap` lookupTitle >>= assertEq (Just valueA)

      , testCase "Should have `basename` key"
        $ definition `rmap` lookupBasename >>= assertEq (Just valueBase)
      ]



testPermalink :: TestTree
testPermalink =
  let
    dictionary = fmap (Contrib.permalink "index") example_md
    definition = fmap (List.head) dictionary
  in
    testGroup
      "Permalink"
      [ testCase "Should have the correct `localPath`"
        $ definition `rmap` Shikensu.localPath >>= assertEq "example/index.md"

      , testCase "Should have the correct `parentPath`"
        $ definition `rmap` Shikensu.parentPath >>= assertEq (Just "../")

      , testCase "Should have the correct `pathToRoot`"
        $ definition `rmap` Shikensu.pathToRoot >>= assertEq "../"
      ]



testPrefixDirname :: TestTree
testPrefixDirname =
  let
    dictionary = fmap (Contrib.prefixDirname "prefix/") (list "tests/**/example.md")
    definition = fmap List.head dictionary
  in
    testCase "Should `prefixDirname`"
      $ definition `rmap` Shikensu.dirname >>= assertEq "prefix/fixtures"



testRead :: TestTree
testRead =
  let
    dictionary = example_md >>= Contrib.IO.read
    definition = fmap List.head dictionary
  in
    testCase "Should `read`"
      $ definition
        <&> Shikensu.content
        <&> fmap Text.decodeUtf8
        >>= assertEq (Just (Text.pack "# Example\n"))



testRename :: TestTree
testRename =
  let
    dictionary = fmap (Contrib.rename "example.md" "renamed.md") example_md
    definition = fmap (List.head) dictionary
  in
    testCase "Should `rename`"
      $ definition `rmap` Shikensu.localPath >>= assertEq "renamed.md"



testRenameExt :: TestTree
testRenameExt =
  let
    dictionary = fmap (Contrib.renameExt ".md" ".html") example_md
    definition = fmap (List.head) dictionary
  in
    testCase "Should `renameExt`"
      $ definition `rmap` Shikensu.extname >>= assertEq ".html"



testRenderContent :: TestTree
testRenderContent =
  let
    dictionary = fmap (Contrib.renderContent renderer) (example_md >>= Contrib.IO.read)
    definition = fmap (List.head) dictionary
    expectedResult = Just (Text.pack "<html># Example\n</html>")
  in
    testCase "Should `renderContent`"
      $ definition
        <&> Shikensu.content
        <&> fmap Text.decodeUtf8
        >>= assertEq expectedResult



testWrite :: TestTree
testWrite =
  let
    destination = "tests/build/"
    dictionary = list "tests/**/example.md" >>= Contrib.IO.read >>= Contrib.IO.write destination
    definition = fmap List.head dictionary
  in
    testCase "Should `write`"
      $ definition
          <&> Shikensu.rootDirname
          >>= \r -> Text.readFile (joinPath [r, destination, "fixtures/example.md"])
          >>= \c -> assertEq "# Example\n" (Text.unpack c)
