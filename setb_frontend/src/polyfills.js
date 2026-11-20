// Must be imported before anything that pulls in the Primus SDK: some of its dependencies (Solana utils)
// expect Node's global Buffer. ES imports are hoisted, so this has to live in its own module.
import { Buffer } from "buffer";

if (typeof window !== "undefined" && !window.Buffer) window.Buffer = Buffer;
