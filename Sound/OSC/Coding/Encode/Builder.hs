-- | Optimised encode function for OSC packets.
module Sound.OSC.Coding.Encode.Builder
    (build_packet
    ,encodeMessage
    ,encodeBundle
    ,encodePacket
    ,encodePacket_strict) where

import Data.Word {- base -}

import qualified Data.Binary.IEEE754 as I {- data-binary-ieee754 -}
import qualified Data.ByteString as S {- bytestring -}
import qualified Data.ByteString.Lazy as L {- bytestring -}
import qualified Blaze.ByteString.Builder as B {- bytestring -}
import qualified Blaze.ByteString.Builder.Char8 as B {- bytestring -}

import qualified Sound.OSC.Coding.Byte as Byte {- hosc -}
import Sound.OSC.Datum {- hosc -}
import Sound.OSC.Packet {- hosc -}
import Sound.OSC.Time {- hosc -}

-- | Generate a list of zero bytes for padding.
padding :: Integral i => i -> [Word8]
padding n = replicate (fromIntegral n) 0

-- | Nul byte (0) and then zero padding.
nul_and_padding :: Int -> B.Builder
nul_and_padding n = B.fromWord8s (0 : padding (Byte.align n))

-- Encode a string with zero padding.
build_ascii :: ASCII -> B.Builder
build_ascii s = B.fromByteString s `mappend` nul_and_padding (S.length s + 1)

-- Encode a string with zero padding.
build_string :: String -> B.Builder
build_string s = B.fromString s `mappend` nul_and_padding (length s + 1)

-- Encode a byte string with prepended length and zero padding.
build_bytes :: L.ByteString -> B.Builder
build_bytes s = B.fromInt32be (fromIntegral (L.length s))
                `mappend` B.fromLazyByteString s
                `mappend` B.fromWord8s (padding (Byte.align (L.length s)))

-- Encode an OSC datum.
build_datum :: Datum -> B.Builder
build_datum d =
    case d of
      Int32 i -> B.fromInt32be (fromIntegral i)
      Int64 i -> B.fromInt64be (fromIntegral i)
      Float n -> B.fromWord32be (I.floatToWord (realToFrac n))
      Double n -> B.fromWord64be (I.doubleToWord n)
      TimeStamp t -> B.fromWord64be (fromIntegral (ntpr_to_ntpi t))
      ASCII_String s -> build_ascii s
      Midi (MIDI b0 b1 b2 b3) -> B.fromWord8s [b0,b1,b2,b3]
      Blob b -> build_bytes b

-- Encode an OSC 'Message'.
build_message :: Message -> B.Builder
build_message (Message c l) =
    mconcat [build_string c
            ,build_ascii (descriptor l)
            ,mconcat (map build_datum l)]

-- Encode an OSC 'Bundle'.
build_bundle_ntpi :: NTP64 -> [Message] -> B.Builder
build_bundle_ntpi t l =
    mconcat [B.fromLazyByteString Byte.bundleHeader
            ,B.fromWord64be t
            ,mconcat (map (build_bytes . B.toLazyByteString . build_message) l)]

-- | Builder for an OSC 'Packet'.
build_packet :: Packet -> B.Builder
build_packet o =
    case o of
      Packet_Message m -> build_message m
      Packet_Bundle (Bundle t m) -> build_bundle_ntpi (ntpr_to_ntpi t) m

{-# INLINE encodeMessage #-}
{-# INLINE encodeBundle #-}
{-# INLINE encodePacket #-}
{-# INLINE encodePacket_strict #-}

{- | Encode an OSC 'Message'.

> let b = L.pack [47,103,95,102,114,101,101,0,44,105,0,0,0,0,0,0]
> encodeMessage (Message "/g_free" [Int32 0]) == b

-}
encodeMessage :: Message -> L.ByteString
encodeMessage = B.toLazyByteString . build_packet . Packet_Message

-- | Encode an OSC 'Bundle'.
encodeBundle :: Bundle -> L.ByteString
encodeBundle = B.toLazyByteString . build_packet . Packet_Bundle

-- | Encode an OSC 'Packet'.
encodePacket :: Packet -> L.ByteString
encodePacket = B.toLazyByteString . build_packet

-- | Encode an OSC 'Packet' to a strict 'S.ByteString'.
encodePacket_strict :: Packet -> S.ByteString
encodePacket_strict = B.toByteString . build_packet
