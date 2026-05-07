import { CanonicalVerifier } from "@/components/CanonicalVerifier";
import { PageHeader } from "@/components/primitives/PageHeader";
import { TerminalPanel } from "@/components/primitives/TerminalPanel";

export default function VerifyPage() {
  return (
    <div className="space-y-10">
      <PageHeader
        article="ARTICLE V"
        kicker="OFFICE OF VERIFICATION"
        title={<><em className="italic">Authenticate</em> the bearer.</>}
        lede={
          <>
            Confirm any address is a canonical Xythum mirror — issued by the
            official factory, holding a valid attestation. One call, one truth.
          </>
        }
        stamp={{ text: "ON DEMAND", meta: "ANY CHAIN · ANY ADDRESS", tone: "leaf" }}
      />

      <CanonicalVerifier />

      <section className="grid grid-cols-12 gap-6">
        <div className="col-span-12 lg:col-span-7">
          <TerminalPanel label="INTEGRATOR · ONE-LINE CHECK" status="idle" meta="SOLIDITY · TYPESCRIPT">
            <div className="p-6 font-mono text-[12px] leading-7 text-ink-page">
              <div className="text-leaf-2">// Solidity</div>
              <div>bool canonical = ICanonicalFactory(factory).isCanonical(tokenAddress);</div>
              <div className="mt-4 text-leaf-2">// TypeScript (viem)</div>
              <div>{`const result = await publicClient.readContract({`}</div>
              <div className="pl-4">{`address: factoryAddress,`}</div>
              <div className="pl-4">{`abi: canonicalFactoryAbi,`}</div>
              <div className="pl-4">{`functionName: "isCanonical",`}</div>
              <div className="pl-4">{`args: [tokenAddress],`}</div>
              <div>{`});`}</div>
            </div>
          </TerminalPanel>
        </div>
        <div className="col-span-12 lg:col-span-5">
          <div className="parchment passport-corner p-6 h-full">
            <div className="font-mono text-[9px] uppercase tracking-stamp text-leaf-2 mb-2">
              VERIFICATION GUARANTEE
            </div>
            <div className="font-display italic text-2xl md:text-3xl text-ink-deep leading-tight">
              &ldquo;If the factory hasn&apos;t stamped it, it isn&apos;t canonical.&rdquo;
            </div>
            <div className="mt-4 font-mono text-[9px] uppercase tracking-stamp text-ink-deep/50">
              REGISTRAR · OFFICIAL SEAL
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
